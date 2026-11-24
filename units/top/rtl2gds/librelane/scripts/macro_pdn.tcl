source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
read_current_odb

set block [ord::get_db_block]
set tech  [ord::get_db_tech]
set dbu   [$block getDbUnitsPerMicron]

proc to_dbu {v} {
    global dbu
    return [expr {int(round($v * $dbu))}]
}

set inst_name   $::env(MACRO_STUB_INSTANCE)
set h_layer     $::env(MACRO_STUB_H_LAYER)
set v_layer     $::env(MACRO_STUB_V_LAYER)
set pin_names   [list $::env(MACRO_STUB_VDD_PIN) $::env(MACRO_STUB_VSS_PIN)]
set len_left    [to_dbu $::env(MACRO_STUB_LEFT_LENGTH)]
set len_right   [to_dbu $::env(MACRO_STUB_RIGHT_LENGTH)]
set len_bottom  [to_dbu $::env(MACRO_STUB_BOTTOM_LENGTH)]
set len_top     [to_dbu $::env(MACRO_STUB_TOP_LENGTH)]
set overlap     [to_dbu $::env(MACRO_STUB_OVERLAP)]
set tol         [to_dbu 30.0]

set inst [$block findInst $inst_name]
if {$inst == "NULL"} {
    utl::error FLW 900 "Macro instance '$inst_name' not found."
}

set master [$inst getMaster]
set mw     [$master getWidth]
set mh     [$master getHeight]
set bb     [$inst getBBox]
set orient [$inst getOrient]
if {$orient ni {R0 MX MY R180}} {
    utl::error FLW 902 "Orientation $orient of '$inst_name' is not supported (R0, MX, MY, R180 only)."
}
set flip_x [expr {$orient in {MY R180}}]
set flip_y [expr {$orient in {MX R180}}]

proc add_stub {net layer x1 y1 x2 y2} {
    set swires [$net getSWires]
    if {[llength $swires] == 0} {
        set sw [odb::dbSWire_create $net "ROUTED"]
    } else {
        set sw [lindex $swires 0]
    }
    odb::dbSBox_create $sw $layer $x1 $y1 $x2 $y2 "STRIPE"
}

# mode "h": pin shapes touching the left/right macro edge get horizontal stubs.
# mode "v": pin shapes touching the bottom/top macro edge get vertical stubs.
# Returns {number_of_stubs number_of_skipped_shapes}.
proc process_layer {layer_name mode} {
    global block tech inst master mw mh bb flip_x flip_y tol overlap pin_names
    global len_left len_right len_bottom len_top inst_name

    set layer [$tech findLayer $layer_name]
    if {$layer == "NULL"} {
        utl::error FLW 901 "Layer '$layer_name' not found."
    }

    set count 0
    set skipped 0

    foreach pin_name $pin_names {
        set mterm [$master findMTerm $pin_name]
        if {$mterm == "NULL"} {
            utl::error FLW 903 "Pin '$pin_name' not found on master [$master getName]."
        }
        set iterm [$inst findITerm $pin_name]
        set net [$iterm getNet]
        if {$net == "NULL"} {
            utl::error FLW 904 "Pin '$pin_name' of '$inst_name' is not connected to a net (check global connections)."
        }

        foreach mpin [$mterm getMPins] {
            foreach box [$mpin getGeometry] {
                if {[[$box getTechLayer] getName] ne $layer_name} { continue }

                # Pin shape in master coordinates -> placed coordinates
                set px1 [$box xMin]; set px2 [$box xMax]
                set py1 [$box yMin]; set py2 [$box yMax]
                if {$flip_x} { set t [expr {$mw - $px2}]; set px2 [expr {$mw - $px1}]; set px1 $t }
                if {$flip_y} { set t [expr {$mh - $py2}]; set py2 [expr {$mh - $py1}]; set py1 $t }
                set x1 [expr {[$bb xMin] + $px1}]; set x2 [expr {[$bb xMin] + $px2}]
                set y1 [expr {[$bb yMin] + $py1}]; set y2 [expr {[$bb yMin] + $py2}]

                if {$mode eq "h"} {
                    set on_a [expr {abs($x1 - [$bb xMin]) <= $tol}]   ;# left
                    set on_b [expr {abs($x2 - [$bb xMax]) <= $tol}]   ;# right
                    if {!$on_a && !$on_b} { incr skipped; continue }
                    set ov [expr {min($overlap, $x2 - $x1)}]
                    if {$on_a && $len_left > 0} {
                        add_stub $net $layer [expr {$x1 - $len_left}] $y1 [expr {$x1 + $ov}] $y2
                        incr count
                    }
                    if {$on_b && $len_right > 0} {
                        add_stub $net $layer [expr {$x2 - $ov}] $y1 [expr {$x2 + $len_right}] $y2
                        incr count
                    }
                } else {
                    set on_a [expr {abs($y1 - [$bb yMin]) <= $tol}]   ;# bottom
                    set on_b [expr {abs($y2 - [$bb yMax]) <= $tol}]   ;# top
                    if {!$on_a && !$on_b} { incr skipped; continue }
                    set ov [expr {min($overlap, $y2 - $y1)}]
                    if {$on_a && $len_bottom > 0} {
                        add_stub $net $layer $x1 [expr {$y1 - $len_bottom}] $x2 [expr {$y1 + $ov}]
                        incr count
                    }
                    if {$on_b && $len_top > 0} {
                        add_stub $net $layer $x1 [expr {$y2 - $ov}] $x2 [expr {$y2 + $len_top}]
                        incr count
                    }
                }
            }
        }
    }
    return [list $count $skipped]
}

set total 0

lassign [process_layer $h_layer h] n s
puts "Macro PDN stubs: $n horizontal stubs on $h_layer (left/right edges), $s pin shapes not on those edges skipped."
incr total $n

lassign [process_layer $v_layer v] n s
puts "Macro PDN stubs: $n vertical stubs on $v_layer (bottom/top edges), $s pin shapes not on those edges skipped."
incr total $n

if {$total == 0} {
    utl::warn FLW 905 "No stubs were created. Check pin names, layers and whether pins reach the macro edges."
}


##########################################################################################
# Partial Placement Blockage above and below DCV SRAMs. 

# Sucht eine Instanz: erst exakt, dann per Glob-Muster (* und ?).
# Backslashes aus Netlist-Namen werden beim Vergleich ignoriert.
proc find_inst_any {block pattern} {
    set inst [$block findInst $pattern]
    if {$inst ne "NULL"} {
        return $inst
    }

    set matches {}
    foreach i [$block getInsts] {
				set name [string map {"\\" ""} [$i getName]]
        if {[string match $pattern $name]} {
            lappend matches $i
        }
    }

    switch [llength $matches] {
        0 { error "Instanz nicht gefunden: $pattern" }
        1 { return [[lindex $matches 0] getName] }
        default {
            set names [lmap m $matches {$m getName}]
            error "Instanzmuster nicht eindeutig: $pattern -> $names"
        }
    }
}

set block [ord::get_db_block]

# Trennzeichen (/ . \) und ':' durch * bzw. ? abdecken
set inst_a [find_inst_any $block "*4?left_line_inst*u_ram"]
set inst_b [find_inst_any $block "*6?left_line_inst*u_ram"]
set inst_c [find_inst_any $block "diowas_top_i*efpga_subsystem_top_inst"]

set bb_a [[$block findInst $inst_a] getBBox]
set bb_b [[$block findInst $inst_b] getBBox]
set bb_c [[$block findInst $inst_c] getBBox]

## --- Koordinaten (in DBU) ---
## Linke untere Ecke: aus der linken oberen Ecke von inst_a (xMin, yMax)
#set x_ll [$bb_a xMin]
#set y_ll [$bb_a yMax]
#
## Rechte obere Ecke:
##   x aus der rechten oberen Ecke von inst_b (xMax)
##   y aus der Unterkante von inst_c (yMin)
#set x_ur [$bb_b xMax]
#set y_ur [$bb_c yMin]
#
# --- Koordinaten (in DBU) ---
# Linke untere Ecke: aus der linken oberen Ecke von inst_a (xMin, yMax)
set x_ll [expr [$bb_c xMin] - [to_dbu 150.0]]
set y_ll [expr [$bb_c yMin] - [to_dbu 150.0]]

# Rechte obere Ecke:
#   x aus der rechten oberen Ecke von inst_b (xMax)
#   y aus der Unterkante von inst_c (yMin)
set x_ur [expr [$bb_c xMin] + [to_dbu 400.0]]
set y_ur [expr [$bb_c yMin] + [to_dbu   0.0]]

if {$x_ur <= $x_ll || $y_ur <= $y_ll} {
    error "Ungueltiges Rechteck: ($x_ll,$y_ll) - ($x_ur,$y_ur)"
}

# --- Partielle Blockage anlegen ---
set blk [odb::dbBlockage_create $block $x_ll $y_ll $x_ur $y_ur]
$blk setMaxDensity 30.0   ;# max. 20 % der Fläche dürfen mit Zellen belegt werden

# --- Kontrolle (Ausgabe in µm) ---
set dbu [$block getDbUnitsPerMicron]
puts [format "Blockage: (%.3f, %.3f) - (%.3f, %.3f) um, max density %.1f %%" \
    [expr {double($x_ll)/$dbu}] [expr {double($y_ll)/$dbu}] \
    [expr {double($x_ur)/$dbu}] [expr {double($y_ur)/$dbu}] [$blk getMaxDensity]]


##################################
## --- Instanznamen ---
#set inst_a "diowas_top_i/dc_cam_if_top_inst/bayer_interpolator_inst/mux_inst/left_line_n1_left_line_inst.u_ram"
#set inst_b "diowas_top_i/dc_cam_if_top_inst/bayer_interpolator_inst/mux_inst/left_line_n3_left_line_inst.u_ram"
#set inst_c "diowas_top_i/dc_cam_if_top_inst/bayer_interpolator_inst/mux_inst/left_line_n3_left_line_inst.u_ram"
#
#set block [ord::get_db_block]
#
## --- Instanzen holen und prüfen ---
#foreach n [list $inst_a $inst_b $inst_c] {
#    if {[$block findInst $n] eq "NULL"} {
#        error "Instanz nicht gefunden: $n"
#    }
#}
#set bb_a [[$block findInst $inst_a] getBBox]
#set bb_b [[$block findInst $inst_b] getBBox]
#set bb_c [[$block findInst $inst_c] getBBox]
#
## --- Koordinaten (in DBU) ---
## Linke untere Ecke: aus der linken oberen Ecke von inst_a (xMin, yMax)
#set x_ll [$bb_a xMin]
#set y_ll [to_dbu 346.0]
#
## Rechte obere Ecke:
##   x aus der rechten oberen Ecke von inst_b (xMax)
##   y aus der Unterkante von inst_c (yMin)
#set x_ur [$bb_b xMax]
#set y_ur [$bb_c yMin]
#
#if {$x_ur <= $x_ll || $y_ur <= $y_ll} {
#    error "Ungueltiges Rechteck: ($x_ll,$y_ll) - ($x_ur,$y_ur)"
#}
#
## --- Partielle Blockage anlegen ---
#set blk [odb::dbBlockage_create $block $x_ll $y_ll $x_ur $y_ur]
#$blk setMaxDensity 45.0   ;# max. 20 % der Fläche dürfen mit Zellen belegt werden
#
## --- Kontrolle (Ausgabe in µm) ---
#set dbu [$block getDbUnitsPerMicron]
#puts [format "Blockage: (%.3f, %.3f) - (%.3f, %.3f) um, max density %.1f %%" \
#    [expr {double($x_ll)/$dbu}] [expr {double($y_ll)/$dbu}] \
#    [expr {double($x_ur)/$dbu}] [expr {double($y_ur)/$dbu}] [$blk getMaxDensity]]
#
#
###########################################################################################
## Partial Placement Blockage between eFPGA and AXI SRAMs
## --- Instanznamen ---
#set inst_a "diowas_top_i/axi_sram1_inst.sram_b3"
#set inst_b "diowas_top_i/axi_sram0_inst.sram_b0"
#set inst_c "diowas_top_i/efpga_subsystem_top_inst"
#
#set block [ord::get_db_block]
#
## --- Instanzen holen und prüfen ---
#foreach n [list $inst_a $inst_b $inst_c] {
#    if {[$block findInst $n] eq "NULL"} {
#        error "Instanz nicht gefunden: $n"
#    }
#}
#set bb_a [[$block findInst $inst_a] getBBox]
#set bb_b [[$block findInst $inst_b] getBBox]
#set bb_c [[$block findInst $inst_c] getBBox]
#
## --- Koordinaten (in DBU) ---
## Linke untere Ecke: aus der linken oberen Ecke von inst_a (xMin, yMax)
#set x_ll [$bb_a xMin]
#set y_ll [$bb_a yMax]
#
## Rechte obere Ecke:
##   x aus der rechten oberen Ecke von inst_b (xMax)
##   y aus der Unterkante von inst_c (yMin)
#set x_ur [$bb_b xMax]
#set y_ur [$bb_c yMin]
#
#if {$x_ur <= $x_ll || $y_ur <= $y_ll} {
#    error "Ungueltiges Rechteck: ($x_ll,$y_ll) - ($x_ur,$y_ur)"
#}
#
## --- Partielle Blockage anlegen ---
#set blk [odb::dbBlockage_create $block $x_ll $y_ll $x_ur $y_ur]
#$blk setMaxDensity 35.0   ;# max. 20 % der Fläche dürfen mit Zellen belegt werden
#
## --- Kontrolle (Ausgabe in µm) ---
#set dbu [$block getDbUnitsPerMicron]
#puts [format "Blockage: (%.3f, %.3f) - (%.3f, %.3f) um, max density %.1f %%" \
#    [expr {double($x_ll)/$dbu}] [expr {double($y_ll)/$dbu}] \
#    [expr {double($x_ur)/$dbu}] [expr {double($y_ur)/$dbu}] [$blk getMaxDensity]]
#

##########################################################################################


write_views


# stdcell power pins
add_global_connection -net {VDD} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -pin_pattern {^VDDCE$}

add_global_connection -net {VSS} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -pin_pattern {^VSSE$}

add_global_connection -net {VDD} -pin_pattern {^VPWR$} -power
add_global_connection -net {VSS} -pin_pattern {^VGND$} -ground

# padframe core power pins
add_global_connection -net {VDD} -pin_pattern {^vdd$} -power
add_global_connection -net {VSS} -pin_pattern {^vss$} -ground

# padframe io power pins
add_global_connection -net {IOVDD} -pin_pattern {^iovdd$} -power
add_global_connection -net {IOVSS} -pin_pattern {^iovss$} -ground

global_connect

# Create a region covering the full core area
set region [odb::dbRegion_create [ord::get_db_block] Die]

set core_area [[ord::get_db_block] getCoreArea]

puts $core_area
puts [$core_area xMin]
puts [$core_area yMin]
puts [$core_area xMax]
puts [$core_area yMax]


odb::dbBox_create $region {362} {362} {3238} {4638}
#[$core_area xMin] [$core_area yMin] [$core_area xMax] [$core_area yMax]

# core voltage domain
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

# stdcell grid
define_pdn_grid -name {grid} -voltage_domains {CORE}

add_pdn_ring \
	-grid {grid} \
	-layers {TopMetal1 TopMetal2} \
	-widths {15.0} \
	-spacings {2.0} \
	-core_offsets {4.5} \
	-connect_to_pads

add_pdn_stripe \
	-grid {grid} \
	-layer {Metal1} \
	-width {0.44} \
	-pitch {7.56} \
	-offset {0} \
	-followpins \
	-extend_to_core_ring

add_pdn_stripe \
	-grid {grid} \
	-layer {TopMetal1} \
	-width {5.000} \
	-pitch {75.6} \
	-offset {13.600} \
	-extend_to_core_ring

add_pdn_stripe \
	-grid {grid} \
	-layer {TopMetal2} \
	-width {5.000} \
	-pitch {75.6} \
	-offset {13.600} \
	-extend_to_core_ring

add_pdn_connect -grid {grid} -layers {Metal1 TopMetal1}
add_pdn_connect -grid {grid} -layers {Metal5 TopMetal2}
add_pdn_connect -grid {grid} -layers {TopMetal1 TopMetal2}

### eFPGA grid
#define_pdn_grid \
#    -macro \
#    -grid_over_pg_pins \
#    -instances "diowas_top_i/efpga_inst.efpga_top_inst/eFPGA_inst" \
#    -name eFPGA \
#    -starts_with POWER
#
#add_pdn_connect \
#    -grid eFPGA \
#    -layers "TopMetal1 TopMetal2"

# sram grid
define_pdn_grid \
    -macro \
    -instances "\
      diowas_top_i/axi_sram0_inst.sram_b0 \
      diowas_top_i/axi_sram0_inst.sram_b1 \
      diowas_top_i/axi_sram0_inst.sram_b2 \
      diowas_top_i/axi_sram0_inst.sram_b3 \
      diowas_top_i/axi_sram1_inst.sram_b0 \
      diowas_top_i/axi_sram1_inst.sram_b1 \
      diowas_top_i/axi_sram1_inst.sram_b2 \
      diowas_top_i/axi_sram1_inst.sram_b3" \
    -name axi_sram \
    -starts_with POWER

add_pdn_stripe \
    -grid axi_sram \
    -layer Metal5 \
    -width 2.81 \
    -pitch 11.24 \
    -offset 2.81 \
    -spacing 2.81 \
    -nets "VSS VDD" \
    -starts_with POWER

add_pdn_connect \
    -grid axi_sram \
    -layers "Metal4 Metal5"
add_pdn_connect \
    -grid axi_sram \
    -layers "Metal5 TopMetal1"


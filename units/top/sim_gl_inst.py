#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 DI-OWAS team
# SPDX-License-Identifier: Apache-2.0
"""Gate-level netlists of single diowas_top instances for sim_octram.mk (GL_INST option).

Called by sim_octram.mk (make -f sim_octram.mk gl_inst / gl_netlists), from units/top:
    ./sim_gl_inst.py synth <instance>     -> build/gl_inst/<instance>_gl.v (module <instance>_gl)
    ./sim_gl_inst.py top <out.v> <inst>.. -> copy of diowas_top.v, the instances use <instance>_gl

Synthesis: yosys elaborates the whole diowas_top (chip path: no TECH_FPGA, IHP_CMOS5L and
OCTRAM_RESET_CYCLES as in the simulation), so every instance gets exactly its parameters.
Then only the instance's module is kept, flattened and mapped to the SG13CMOS5L cells
(typ lib, zero delay). SRAM macros and the eFPGA stay black boxes (simulated by their models).
Environment, set by sim_octram.mk: GL_INST_RTL (RTL files of diowas_top without the eFPGA),
CMOS5L_PDK (ihp-sg13cmos5l dir), OCTRAM_RESET_CYCLES. Optional: YOSYS (default yosys).
"""
import os, re, subprocess, sys
from glob import glob
from pathlib import Path

TOP = Path("src/rtl/diowas_top.v")
PDK = Path(os.environ.get("CMOS5L_PDK", ""))
LIB = PDK / "libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib"
TIE_HI = "sg13cmos5l_tiehi L_HI"  # tie-high cell and its output pin
TIE_LO = "sg13cmos5l_tielo L_LO"
OUT = Path("build/gl_inst")
YOSYS = os.environ.get("YOSYS", "yosys")
DEFINES = ["IHP_CMOS5L", f"OCTRAM_RESET_CYCLES={os.environ.get('OCTRAM_RESET_CYCLES', '')}"]

RTL = os.environ.get("GL_INST_RTL", "").split()
# black boxes: interfaces only (the SRAM models don't parse in yosys: their port lists are extracted)
BLACKBOX = ["src/sim/efpga_subsystem_stub.sv"]
SRAM_MODELS = [f for f in sorted(glob(str(PDK / "libs.ref/sg13cmos5l_sram/verilog/RM_IHPSG13_*.v"))) if "behavioral" not in f]

# wires the TB monitors probe inside a GL instance: kept by name in the flat netlist
KEEP = {"cryptoCore_inst": ["dma_busy"]}

WRITTEN = set()  # generated files already written in this run


def strip_comments(text):
    """Blank // and /* */ comments, keep offsets."""
    return re.sub(r"//[^\n]*|/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m[0]), text, flags=re.S)


def yosys(script, log):
    script_file = log.with_suffix(".ys")
    script_file.write_text(script)
    subprocess.run([YOSYS, "-q", "-l", str(log), str(script_file)], check=True)


def sram_blackboxes():
    """Module header and port declarations of the SRAM macro models (written once per run)."""
    out = OUT / "sram_blackbox.v"
    if out in WRITTEN:
        return out
    stubs = []
    for f in SRAM_MODELS:
        text = strip_comments(Path(f).read_text())
        m = re.search(r"\bmodule\s+\w+\s*\(.*?\);", text, re.S)
        if not m:
            continue
        decls = re.findall(r"^\s*(?:input|output|inout)\b[^;]*;", text[m.end():], re.M)
        stubs.append(m[0] + "\n" + "\n".join(decls) + "\nendmodule\n")
    out.write_text("(* blackbox *)\n".join([""] + stubs))
    WRITTEN.add(out)
    return out


def read_design():
    defs = " ".join(f"-D{d}" for d in DEFINES)
    lines = [f"read_liberty -lib {LIB}"]
    lines += [f"read_verilog -sv -lib {defs} {f}" for f in BLACKBOX + [sram_blackboxes()]]
    lines += [f"read_verilog -sv -defer {defs} {' '.join(RTL)}",
              "hierarchy -check -top diowas_top"]
    return "\n".join(lines) + "\n"


def synth(inst):
    OUT.mkdir(parents=True, exist_ok=True)
    # pass 1: module (with its parameters) of the instance
    cell_dump = OUT / f"{inst}_cell.txt"
    yosys(read_design() + f"tee -q -o {cell_dump} dump diowas_top/c:{inst}\n", OUT / f"{inst}_elab.log")
    m = re.search(r"^\s*cell\s+(\S+)\s+\\" + re.escape(inst) + r"\s*$", cell_dump.read_text(), re.M)
    if not m:
        sys.exit(f"{inst}: instance not found in diowas_top")
    module = m[1]
    gl_module = f"{inst}_gl"
    keep = "".join(f"setattr -set keep 1 {gl_module}/w:{w}\n" for w in KEEP.get(inst, []))
    # pass 2: keep that module only, flatten and map
    yosys(read_design() + f"""hierarchy -top {module}
rename {module} {gl_module}
{keep}synth -flatten -top {gl_module}
setattr -unset init
delete t:$print
dfflibmap -liberty {LIB}
abc -liberty {LIB}
hilomap -singleton -hicell {TIE_HI} -locell {TIE_LO}
opt_clean -purge
check -assert
tee -o {OUT}/{inst}_stat.txt stat -liberty {LIB}
write_verilog -noattr -noexpr -nohex -nodec {OUT}/{gl_module}.v
""", OUT / f"{inst}.log")
    print(f"{inst} ({module}): {OUT}/{gl_module}.v")


def top_copy(out, insts):
    """diowas_top.v with "<module> #(...) <inst> (" replaced by "<inst>_gl <inst> (", ifdefs included."""
    text = TOP.read_text()
    clean = strip_comments(text)
    for inst in insts:
        m = re.search(r"\b" + re.escape(inst) + r"\s*\(", clean)
        if not m:
            sys.exit(f"{inst}: instance not found in {TOP}")
        start = clean.rfind(";", 0, m.start()) + 1
        # keep a leading `endif / `else line of a preceding block, cut from the next line
        start = clean.find("\n", start) + 1
        while re.match(r"[ \t]*(`endif|`else)?[ \t]*\n", clean[start:]):
            start = clean.find("\n", start) + 1
        text_before = text[start:m.start()]
        if text_before.count("`ifdef") + text_before.count("`ifndef") != text_before.count("`endif"):
            sys.exit(f"{inst}: unbalanced ifdefs before the instance, can't replace")
        replacement = f"  // gate level (sim_gl_inst.py)\n  {inst}_gl "
        text = text[:start] + replacement + text[m.start():]
        clean = clean[:start] + replacement + clean[m.start():]
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text(text)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("synth", "top"):
        sys.exit(__doc__)
    if sys.argv[1] == "synth":
        missing = [v for v in ("GL_INST_RTL", "CMOS5L_PDK", "OCTRAM_RESET_CYCLES") if not os.environ.get(v)]
        if missing:
            sys.exit(f"{', '.join(missing)} not set: run it through make -f sim_octram.mk gl_netlists")
        if not LIB.exists():
            sys.exit(f"cell library not found: {LIB}\nset CMOS5L_PDK to the ihp-sg13cmos5l directory")
        for inst in sys.argv[2:]:
            synth(inst)
    else:
        top_copy(sys.argv[2], sys.argv[3:])


if __name__ == "__main__":
    main()

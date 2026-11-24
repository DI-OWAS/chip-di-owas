import re
import sys
from reader import click_odb, click, odb  # noqa: F401


def clean(name):
    return name.replace("\\", "")


def buf_pins(inst):
    ins = [it for it in inst.getITerms() if it.isInputSignal()]
    outs = [it for it in inst.getITerms() if it.isOutputSignal()]
    if len(ins) != 1 or len(outs) != 1:
        return None
    return ins[0], outs[0]


def location_of(iterm):
    """Prefer the pin location; fall back to the instance origin."""
    try:
        res = iterm.getAvgXY()
        if res[0]:
            return int(res[1]), int(res[2])
    except Exception:
        pass
    return iterm.getInst().getLocation()


def insert_chain(block, master, count, net_in, sinks, loc, counter):
    """net_in -> buf -> ... -> buf -> sinks (all sinks move to the last net)."""
    sig_type = net_in.getSigType()
    prev = net_in
    new = []
    for _ in range(count):
        name = f"macro_clk_dly_{counter[0]}"
        while block.findInst(name) or block.findNet(f"{name}_net"):
            counter[0] += 1
            name = f"macro_clk_dly_{counter[0]}"
        counter[0] += 1
        buf = odb.dbInst.create(block, master, name)
        out_net = odb.dbNet.create(block, f"{name}_net")
        out_net.setSigType(sig_type)
        a, x = buf_pins(buf)
        a.connect(prev)
        x.connect(out_net)
        buf.setOrient("R0")
        buf.setLocation(*loc)
        buf.setPlacementStatus("PLACED")
        new.append(buf)
        prev = out_net
    for s in sinks:
        s.disconnect()
        s.connect(prev)
    return new


@click.command()
@click_odb
def cli(reader):
    cfg = reader.config
    patterns = [re.compile(p) for p in cfg["MACRO_CLK_DELAY_PATTERNS"]]
    pin_rx = re.compile(cfg["MACRO_CLK_DELAY_PIN_RX"])
    count = int(cfg["MACRO_CLK_DELAY_COUNT"])
    dry = bool(cfg["MACRO_CLK_DELAY_DRY_RUN"])

    master = reader.db.findMaster(cfg["MACRO_CLK_DELAY_BUFFER"])
    if master is None:
        print(f"[ERROR] Buffer '{cfg['MACRO_CLK_DELAY_BUFFER']}' not found.", file=sys.stderr)
        sys.exit(1)

    # (macro name, net name) -> (macro, net, [clock iterms]); one chain per macro and net
    work = {}
    for pat in patterns:
        found = 0
        for inst in reader.block.getInsts():
            if not inst.isBlock():
                continue
            name = inst.getName()
            if not (pat.fullmatch(name) or pat.fullmatch(clean(name))):
                continue
            found += 1
            for it in inst.getITerms():
                if not it.isInputSignal() or it.getNet() is None:
                    continue
                mt = it.getMTerm()
                if str(mt.getSigType()) == "CLOCK" or pin_rx.fullmatch(mt.getName()):
                    k = (name, it.getNet().getName())
                    entry = work.setdefault(k, (inst, it.getNet(), []))
                    if it not in entry[2]:
                        entry[2].append(it)
        if found == 0:
            print(f"[ERROR] Pattern '{pat.pattern}' matched no macro.", file=sys.stderr)
            sys.exit(1)
        print(f"[INFO] '{pat.pattern}': {found} macro(s).")

    if not work:
        print("[ERROR] No macro clock pins found.", file=sys.stderr)
        sys.exit(1)

    for (mname, nname), (inst, net, its) in work.items():
        pins = ",".join(it.getMTerm().getName() for it in its)
        print(f"[INFO]   {mname}: pin(s) {pins} on net {nname}")
    print(f"[INFO] {len(work)} clock input group(s), {count} x {master.getName()} each "
          f"= {len(work) * count} buffer(s).")
    if dry:
        return

    # Only the new buffers may move during legalization.
    locked = []
    for inst in reader.block.getInsts():
        if inst.getPlacementStatus() != "LOCKED":
            locked.append((inst, inst.getPlacementStatus()))
            inst.setPlacementStatus("LOCKED")

    counter = [0]
    for (mname, nname), (inst, net, its) in work.items():
        insert_chain(reader.block, master, count, net, its, location_of(its[0]), counter)

    dpl = reader.design.getOpendp()
    site = reader.rows[0].getSite()
    max_x = int(reader.design.micronToDBU(cfg["PL_MAX_DISPLACEMENT_X"]) / site.getWidth())
    max_y = int(reader.design.micronToDBU(cfg["PL_MAX_DISPLACEMENT_Y"]) / site.getHeight())
    dpl.detailedPlacement(max_x, max_y)

    for inst, status in locked:
        inst.setPlacementStatus(status)


if __name__ == "__main__":
    cli()

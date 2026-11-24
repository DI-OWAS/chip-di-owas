"""OpenROAD (odb) script: connect IO power pads to the horizontal core-ring
segments with vertical Metal4 straps plus a via stack up to the ring layer.

Runs inside `openroad -python`, launched by the IHP.PadPDNConnect step.
"""

import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)


def _bootstrap_odbpy_dir():
    """`reader` lives in LibreLane's own odbpy script directory, which is not
    on sys.path for scripts that live elsewhere."""
    d = os.environ.get("LIBRELANE_ODBPY_DIR")
    if "--odbpy-dir" in sys.argv:
        i = sys.argv.index("--odbpy-dir")
        if i + 1 < len(sys.argv):
            d = sys.argv[i + 1]
    if d and os.path.isdir(d) and d not in sys.path:
        sys.path.insert(0, d)


_bootstrap_odbpy_dir()

import click  # noqa: E402
import odb  # noqa: E402
from reader import click_odb  # noqa: E402

import padpdn_geometry as geo  # noqa: E402


# --------------------------------------------------------------------------
# odb helpers
# --------------------------------------------------------------------------
def box_rect(b):
    return (b.xMin(), b.yMin(), b.xMax(), b.yMax())


def layer_name(box):
    lyr = box.getTechLayer()
    return lyr.getName() if lyr is not None else None


def iterm_net_name(iterm):
    n = iterm.getNet()
    return n.getName() if n is not None else None


def placed_rect(inst, local_rect):
    m = inst.getMaster()
    bb = inst.getBBox()
    return geo.transform_rect(
        local_rect, inst.getOrient(), m.getWidth(), m.getHeight(),
        bb.xMin(), bb.yMin(),
    )


def pin_rects(inst, iterm, lname):
    """Placed rectangles of one instance terminal on one layer."""
    out = []
    for mpin in iterm.getMTerm().getMPins():
        for g in mpin.getGeometry():
            if layer_name(g) == lname:
                out.append(placed_rect(inst, box_rect(g)))
    return out


def find_iterm(inst, pin_name):
    for it in inst.getITerms():
        if it.getMTerm().getName().lower() == pin_name.lower():
            return it
    return None


def swire_shapes(net, lname):
    out = []
    for sw in net.getSWires():
        for sb in sw.getWires():
            if sb.isVia():
                continue
            if layer_name(sb) == lname:
                out.append(box_rect(sb))
    return out


def collect_obstructions(block, lname):
    """Everything on the strap layer that a new wire must keep clear of.

    Entries: (rect, net_name_or_None, tag). The tag is "inst/pin" for pin
    shapes so the target pin itself can be excluded.
    """
    obs = []
    for net in block.getNets():
        for r in swire_shapes(net, lname):
            obs.append((r, net.getName(), "swire:" + net.getName()))
    for inst in block.getInsts():
        m = inst.getMaster()
        if not (m.isBlock() or m.isPad()):
            continue
        for it in inst.getITerms():
            tag = f"{inst.getName()}/{it.getMTerm().getName()}"
            for r in pin_rects(inst, it, lname):
                obs.append((r, iterm_net_name(it), tag))
        for g in m.getObstructions():
            if layer_name(g) == lname:
                obs.append((placed_rect(inst, box_rect(g)), None,
                            f"{inst.getName()}/OBS"))
    return obs


def min_spacing(layer, width):
    for args in ((width,), ()):
        try:
            v = layer.getSpacing(*args)
            if v:
                return v
        except Exception:
            pass
    return 0


def routing_stack(tech, lo, hi):
    layers = [
        l for l in tech.getLayers()
        if l.getType() == "ROUTING"
        and lo.getRoutingLevel() <= l.getRoutingLevel() <= hi.getRoutingLevel()
    ]
    return sorted(layers, key=lambda l: l.getRoutingLevel())


def pick_via(tech, block, bottom, top, max_width):
    """Largest via between two adjacent routing layers that fits max_width."""
    best, best_area = None, -1
    for v in list(tech.getVias()) + list(block.getVias()):
        bl, tl = v.getBottomLayer(), v.getTopLayer()
        if bl is None or tl is None:
            continue
        if bl.getName() != bottom.getName() or tl.getName() != top.getName():
            continue
        bb = v.getBBox()
        if bb is None:
            continue
        w = bb.xMax() - bb.xMin()
        h = bb.yMax() - bb.yMin()
        if w > max_width:
            continue
        if w * h > best_area:
            best, best_area = v, w * h
    return best


def cut_pitch(via, cut_layer):
    cut_w = 0
    for b in via.getBoxes():
        lyr = b.getTechLayer()
        if lyr is not None and lyr.getName() == cut_layer.getName():
            cut_w = max(cut_w, b.xMax() - b.xMin())
    sp = min_spacing(cut_layer, cut_w)
    bb = via.getBBox()
    return max(cut_w + sp, bb.xMax() - bb.xMin())


def parse_specs(specs):
    out = []
    for s in specs:
        parts = s.split(":")
        if len(parts) < 2:
            raise click.ClickException(
                f"bad --pad spec '{s}', expected master_regex:pin[:net]")
        out.append((re.compile(parts[0]), parts[1],
                    parts[2] if len(parts) > 2 and parts[2] else None))
    return out


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
@click.command()
@click.option("--pad", "pad_specs", multiple=True, required=True,
              help="master_regex:pin[:net]; net defaults to the pin's net.")
@click.option("--route-layer", default="Metal4")
@click.option("--ring-layer", default="TopMetal1")
@click.option("--wire-width", type=float, default=3.0, help="um")
@click.option("--clearance", type=float, default=0.5,
              help="um, added on top of the layer min spacing")
@click.option("--straps", type=int, default=2, help="straps per pad pin")
@click.option("--edges", default="top,bottom")
@click.option("--strict/--no-strict", default=True)
@click.option("--odbpy-dir", default=None, help="(used by bootstrap only)")
@click_odb
def cli(reader, pad_specs, route_layer, ring_layer, wire_width, clearance,
        straps, edges, strict, odbpy_dir):
    db = reader.db
    block = reader.block
    tech = db.getTech()
    dbu = block.getDbUnitsPerMicron()
    um = lambda v: int(round(v * dbu))  # noqa: E731

    r_layer = tech.findLayer(route_layer)
    t_layer = tech.findLayer(ring_layer)
    if r_layer is None or t_layer is None:
        raise click.ClickException(
            f"layer not found: {route_layer} / {ring_layer}")

    ca = block.getCoreArea()
    core = (ca.xMin(), ca.yMin(), ca.xMax(), ca.yMax())
    print(f"[PadPDN] core area (dbu): {core}")

    wanted_edges = {e.strip() for e in edges.split(",") if e.strip()}
    specs = parse_specs(pad_specs)
    width = um(wire_width)
    grid = max(tech.getManufacturingGrid(), 1)

    stack = routing_stack(tech, r_layer, t_layer)
    if len(stack) < 2:
        raise click.ClickException(
            f"no routing layers between {route_layer} and {ring_layer}")

    obstructions = collect_obstructions(block, route_layer)
    ring_shapes_cache = {}
    failures, created = [], 0

    pads = []
    for inst in block.getInsts():
        mname = inst.getMaster().getName()
        for rx, pin, net_override in specs:
            if rx.fullmatch(mname):
                pads.append((inst, pin, net_override))
                break
    print(f"[PadPDN] {len(pads)} matching pad instance(s)")

    for inst, pin, net_override in sorted(pads, key=lambda p: p[0].getName()):
        iname = inst.getName()
        bb = inst.getBBox()
        edge = geo.classify_edge(box_rect(bb), core)
        if edge is None or edge not in wanted_edges:
            continue  # left/right edge pads or not requested

        it = find_iterm(inst, pin)
        if it is None:
            failures.append(f"{iname}: master has no pin '{pin}'")
            continue
        net_name = net_override or iterm_net_name(it)
        net = block.findNet(net_name) if net_name else None
        if net is None:
            failures.append(
                f"{iname}/{pin}: no net (pin unconnected and no net given "
                f"in --pad); run global connect first or pass :net")
            continue
        tag = f"{iname}/{it.getMTerm().getName()}"

        pins = pin_rects(inst, it, route_layer)
        if not pins:
            failures.append(f"{iname}/{pin}: no {route_layer} shape on pin")
            continue

        if net_name not in ring_shapes_cache:
            ring_shapes_cache[net_name] = swire_shapes(net, ring_layer)
        segs = geo.horizontal_ring_segments_outside_core(
            ring_shapes_cache[net_name], core, edge)
        if not segs:
            failures.append(
                f"{iname}/{pin}: no horizontal {ring_layer} ring segment of "
                f"net {net_name} outside the core on the {edge} edge")
            continue

        # pin rect with the largest x-overlap with any ring segment
        best = None
        for pr in pins:
            seg = geo.select_ring_segment(segs, pr, width + 2 * um(clearance))
            if seg is None:
                continue
            ov = min(seg[2], pr[2]) - max(seg[0], pr[0])
            if best is None or ov > best[2]:
                best = (pr, seg, ov)
        if best is None:
            failures.append(
                f"{iname}/{pin}: pin and ring segments share no usable x-range")
            continue
        pin_r, seg, _ = best
        ring_yc = int(round(geo.center(seg)[1]))
        pin_yc = int(round(geo.center(pin_r)[1]))

        # via stack (pick per adjacent layer pair)
        levels = []
        ok = True
        ring_h = seg[3] - seg[1]
        for lo, hi in zip(stack[:-1], stack[1:]):
            v = pick_via(tech, block, lo, hi, width)
            if v is None:
                failures.append(
                    f"{iname}/{pin}: no via {lo.getName()}->{hi.getName()} "
                    f"with width <= {wire_width} um")
                ok = False
                break
            levels.append((lo, hi, v))
        if not ok:
            continue

        x_lo = max(pin_r[0], seg[0])
        x_hi = min(pin_r[2], seg[2])
        reg_h = min(width, ring_h)
        region_y = (ring_yc - reg_h // 2, ring_yc - reg_h // 2 + reg_h)
        y_lo = min(pin_yc, region_y[0])
        y_hi = max(pin_yc, region_y[1])

        spacing = min_spacing(r_layer, width) + um(clearance)
        blockers = [r for (r, n, t) in obstructions
                    if n != net_name and t != tag]
        cols = geo.pick_columns(x_lo, x_hi, width, y_lo, y_hi, blockers,
                                spacing, straps, grid)
        if not cols:
            near = sorted({t for (r, n, t) in obstructions
                           if n != net_name and t != tag and geo.overlaps(
                               geo.inflate(r, spacing),
                               (x_lo, y_lo, x_hi, y_hi))})
            failures.append(
                f"{iname}/{pin}: no short-free {route_layer} column between "
                f"pin and ring. Blocked by: {', '.join(near[:8]) or '?'}")
            continue

        sw = odb.dbSWire.create(net, odb.dbWireType.ROUTED)
        half = width // 2
        for xc in cols:
            wx1, wx2 = xc - half, xc - half + width
            odb.dbSBox.create(sw, r_layer, wx1, y_lo, wx2, y_hi,
                              odb.dbWireShapeType.STRIPE)
            region = (wx1, region_y[0], wx2, region_y[1])
            for lo, hi, v in levels:
                cut = lo.getUpperLayer()
                vb = v.getBBox()
                origins = geo.via_array_origins(
                    region, (vb.xMin(), vb.yMin(), vb.xMax(), vb.yMax()),
                    cut_pitch(v, cut) if cut is not None else 0)
                if not origins:
                    failures.append(
                        f"{iname}/{pin}: via {v.getName()} does not fit "
                        f"in landing region")
                    break
                if hi.getName() != t_layer.getName():
                    odb.dbSBox.create(sw, hi, *region,
                                      odb.dbWireShapeType.STRIPE)
                for (vx, vy) in origins:
                    odb.dbSBox.create(sw, v, vx, vy,
                                      odb.dbWireShapeType.STRIPE)
            else:
                # keep later pads/straps from colliding with this strap
                obstructions.append(
                    ((wx1, y_lo, wx2, y_hi), net_name, f"new:{tag}"))
                created += 1
                continue
        print(f"[PadPDN] {iname}/{pin} ({edge}, net {net_name}): "
              f"{len(cols)} strap(s) at x = {cols}")

    print(f"[PadPDN] created {created} strap(s); {len(failures)} problem(s)")
    for f in failures:
        print(f"[PadPDN] PROBLEM: {f}")
    if failures and strict:
        raise click.ClickException(
            f"{len(failures)} pad(s) could not be connected (see log)")


if __name__ == "__main__":
    cli()

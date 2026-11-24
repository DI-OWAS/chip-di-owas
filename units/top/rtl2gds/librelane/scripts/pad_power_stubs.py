"""
Connect the TopMetal1 stubs of the IO cells (pads, fillers, ...) on the top and bottom
edge to the core ring.  Runs inside `openroad -python` (parameters come from PPS_* environment
variables, see main()); the geometry/planning part is pure Python so it can be unit
tested without OpenROAD (see test_pad_power_stubs.py).

All coordinates are integers in database units (dbu).

Conventions
-----------
For every pad the problem is solved in a "u" coordinate that grows towards the core:
  top pads:    u = -y
  bottom pads: u =  y
so that one code path handles both sides.  `flip()` converts a rect between real
and u coordinates (it is its own inverse).
"""
from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Sequence, Tuple

Rect = Tuple[int, int, int, int]  # x1, y1, x2, y2
Shape = Tuple[str, Rect]  # net name, rect


class PlanError(Exception):
    pass


@dataclass
class ViaInfo:
    name: str
    bbox: Rect  # bounding box of the complete via (all layers), relative to its origin
    pitch_x: int
    pitch_y: int


@dataclass
class Params:
    vdd: str
    vss: str
    ext: int  # stub extension for the "extend" case
    off: int  # distance pad inner edge -> via array
    height: int  # via array height
    inset: int  # margin inside the ring stripe for the ring via array
    clearance: int  # Metal4 spacing to foreign Metal4
    min_width: int  # Metal4 minimum width
    via: ViaInfo
    mfg: int


@dataclass
class Plan:
    kind: str  # "extend" | "m4" | "connected" | "skipped"
    boxes: List[Tuple[str, str, Rect]] = field(default_factory=list)  # (layer key, net, rect)
    vias: List[Tuple[str, int, int]] = field(default_factory=list)  # (net, x, y) via origin
    notes: List[str] = field(default_factory=list)


# --------------------------------------------------------------------------- geometry
def flip(side: str, r: Rect) -> Rect:
    if side != "top":
        return r
    x1, y1, x2, y2 = r
    return (x1, -y2, x2, -y1)


def overlap(a: Rect, b: Rect) -> bool:
    """True if the interiors intersect (touching does not count)."""
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def grow(r: Rect, d: int) -> Rect:
    return (r[0] - d, r[1] - d, r[2] + d, r[3] + d)


def subtract_intervals(lo: int, hi: int, forbidden: Sequence[Tuple[int, int]]):
    res, cur = [], lo
    for a, b in sorted(forbidden):
        if b <= cur:
            continue
        if a >= hi:
            break
        if a > cur:
            res.append((cur, a))
        cur = max(cur, b)
    if cur < hi:
        res.append((cur, hi))
    return res


def tile_vias(region: Rect, via: ViaInfo, mfg: int) -> List[Tuple[int, int]]:
    """Origins of a via array whose complete bounding boxes lie inside `region`."""
    rx1, ry1, rx2, ry2 = region
    bx1, by1, bx2, by2 = via.bbox
    vw, vh = bx2 - bx1, by2 - by1
    w, h = rx2 - rx1, ry2 - ry1
    if w < vw or h < vh:
        return []
    nx = (w - vw) // via.pitch_x + 1
    ny = (h - vh) // via.pitch_y + 1
    x0 = rx1 + (w - ((nx - 1) * via.pitch_x + vw)) // 2 - bx1
    y0 = ry1 + (h - ((ny - 1) * via.pitch_y + vh)) // 2 - by1
    ceil = lambda v: -(-v // mfg) * mfg
    x0, y0 = ceil(x0), ceil(y0)
    out = []
    for iy in range(ny):
        for ix in range(nx):
            x, y = x0 + ix * via.pitch_x, y0 + iy * via.pitch_y
            if rx1 <= x + bx1 and x + bx2 <= rx2 and ry1 <= y + by1 and y + by2 <= ry2:
                out.append((x, y))
    return out


# --------------------------------------------------------------------------- planning
def plan_stub(
    side: str,
    net: str,
    stub: Rect,
    pad: Rect,
    rings: Sequence[Shape],
    tm1: Sequence[Shape],
    m4: Sequence[Shape],
    P: Params,
) -> Plan:
    """Plan the fix for one stub (real coordinates in, real coordinates out)."""
    sx1, su1, sx2, su2 = flip(side, stub)
    px1, pu1, px2, pu2 = flip(side, pad)  # pu2 = pad edge facing the core

    own, other = [], []
    for rnet, rr in rings:
        rx1, ru1, rx2, ru2 = flip(side, rr)
        if rx1 > sx1 or rx2 < sx2 or ru2 <= su2:  # must span the stub and lie beyond its end
            continue
        if ru1 <= su2:  # stub end already inside this stripe
            if rnet == net:
                return Plan("connected", notes=["stub already overlaps its ring stripe"])
            raise PlanError("stub overlaps a ring stripe of another net")
        (own if rnet == net else other).append((ru1, ru2, rx1, rx2))
    if not own:
        raise PlanError(f"no {net} ring stripe found beyond the stub")
    own.sort()
    o_u1, o_u2, _, _ = own[0]
    blocked = any(ru1 < o_u1 for ru1, _, _, _ in other)

    plan = Plan("extend" if not blocked else "m4")

    # ------------------------------------------------------------ case A: just extend
    if not blocked:
        gap = o_u1 - su2
        if gap >= P.ext:
            raise PlanError(
                f"gap to ring stripe is {gap} dbu, not bridged by extension of {P.ext} dbu"
            )
        new_u = (sx1, su2, sx2, su2 + P.ext)
        for tnet, tr in tm1:
            if tnet != net and overlap(new_u, flip(side, tr)):
                raise PlanError(f"extension would hit {tnet} TopMetal1 shape {tr}")
        plan.boxes.append(("stub", net, flip(side, new_u)))
        plan.notes.append(f"extended by {P.ext} dbu, overlaps ring stripe by {su2 + P.ext - o_u1} dbu")
        return plan

    # ------------------------------------------------------------ case B: Metal4 bridge
    V = P.via
    vw, vh = V.bbox[2] - V.bbox[0], V.bbox[3] - V.bbox[1]
    arr_u1 = pu2 + P.off
    arr_u2 = arr_u1 + P.height
    if su2 < arr_u2:
        raise PlanError("stub too short for the via array (ends %d dbu before it)" % (arr_u2 - su2))
    via_lo, via_hi = o_u1 + P.inset, o_u2 - P.inset
    if via_hi - via_lo < vh:
        raise PlanError("ring stripe too narrow for the ring via array")

    patch_u = (sx1, arr_u1, sx2, arr_u2)
    forb = []
    for mnet, mr in m4:
        if mnet == P.vdd:  # same net: just merges, nothing to avoid
            continue
        mx1, mu1, mx2, mu2 = flip(side, mr)
        if overlap(grow(patch_u, P.clearance), (mx1, mu1, mx2, mu2)):
            raise PlanError(f"foreign Metal4 ({mnet}) in the via-array patch area")
        if mu2 + P.clearance > arr_u2 and mu1 - P.clearance < via_hi:
            forb.append((mx1 - P.clearance, mx2 + P.clearance))

    free = [
        (a, b) for a, b in subtract_intervals(sx1, sx2, forb) if b - a >= max(P.min_width, vw)
    ]
    if not free:
        return Plan("skipped", notes=["WARNING: Metal4 stripe completely blocked by foreign Metal4 stripes, stub left unconnected"])
    if len(free) > 1 or free[0] != (sx1, sx2):
        plan.notes.append(
            "routed around %d foreign Metal4 stripe(s); %d sub-stripe(s)" % (len(forb), len(free))
        )

    plan.boxes.append(("m4", net, flip(side, patch_u)))
    for a, b in free:
        plan.boxes.append(("m4", net, flip(side, (a, (arr_u1 + arr_u2) // 2, b, via_hi))))
    for x, y in tile_vias(flip(side, patch_u), V, P.mfg):
        plan.vias.append((net, x, y))
    n_top = len(plan.vias)
    for a, b in free:
        for x, y in tile_vias(flip(side, (a, via_lo, b, via_hi)), V, P.mfg):
            plan.vias.append((net, x, y))
    if n_top == 0 or len(plan.vias) == n_top:
        raise PlanError("via array does not fit (no vias placed)")
    plan.notes.append(f"{n_top} vias at stub, {len(plan.vias) - n_top} vias at ring")
    return plan


# --------------------------------------------------------------------------- odb glue
def _enum(odb, enum_name: str, member: str):
    e = getattr(odb, enum_name, None)
    if e is not None and hasattr(e, member):
        return getattr(e, member)
    if hasattr(odb, f"{enum_name}_{member}"):
        return getattr(odb, f"{enum_name}_{member}")
    return member  # let SWIG try the string


def _create(cls_name: str, odb):
    cls = getattr(odb, cls_name)
    return getattr(cls, "create", None) or getattr(odb, f"{cls_name}_create")


def _find_via(tech, bottom: str, top: str, name: str):
    cands = []
    for v in tech.getVias():
        if v.getBottomLayer().getName() == bottom and v.getTopLayer().getName() == top:
            if name and v.getName() != name:
                continue
            cands.append(v)
    if not cands:
        raise PlanError(f"no technology via between {bottom} and {top} (name='{name}')")
    cands.sort(key=lambda v: (len(v.getBoxes()), v.getName()))
    return cands[0]


def _via_info(tech, via, pitch_override: int) -> ViaInfo:
    b, t = via.getBottomLayer().getName(), via.getTopLayer().getName()
    cuts, allb = [], []
    for box in via.getBoxes():
        r = (box.xMin(), box.yMin(), box.xMax(), box.yMax())
        allb.append(r)
        if box.getTechLayer().getName() not in (b, t):
            cuts.append((r, box.getTechLayer()))
    if not cuts:
        raise PlanError(f"via {via.getName()} has no cut shape")
    cx1 = min(r[0] for r, _ in cuts); cy1 = min(r[1] for r, _ in cuts)
    cx2 = max(r[2] for r, _ in cuts); cy2 = max(r[3] for r, _ in cuts)
    spacing = cuts[0][1].getSpacing()
    if pitch_override:
        px = py = pitch_override
    else:
        if spacing <= 0:
            raise PlanError("cut spacing unknown, set PAD_POWER_VIA_CUT_PITCH")
        px, py = cx2 - cx1 + spacing, cy2 - cy1 + spacing
    bbox = (
        min(r[0] for r in allb), min(r[1] for r in allb),
        max(r[2] for r in allb), max(r[3] for r in allb),
    )
    return ViaInfo(via.getName(), bbox, px, py)


def main() -> int:
    import odb  # only available inside openroad -python

    env = os.environ
    um = lambda k, d: float(env.get(k, d) or d)
    in_odb, out_odb, out_def = env["PPS_INPUT_ODB"], env["PPS_OUTPUT_ODB"], env["PPS_OUTPUT_DEF"]
    dry = env.get("PPS_DRY_RUN", "0") == "1"

    db = odb.dbDatabase.create()
    odb.read_db(db, in_odb)
    tech, block = db.getTech(), db.getChip().getBlock()
    dbu = tech.getDbUnitsPerMicron()
    to_dbu = lambda v: int(round(v * dbu))

    vdd, vss = env.get("PPS_VDD_NET", "VDD"), env.get("PPS_VSS_NET", "VSS")
    stub_layer, m4_layer = env.get("PPS_STUB_LAYER", "TopMetal1"), env.get("PPS_STRIPE_LAYER", "Metal4")
    m4 = tech.findLayer(m4_layer)
    tmx = tech.findLayer(stub_layer)
    if m4 is None or tmx is None:
        raise PlanError("layer not found: %s / %s" % (m4_layer, stub_layer))

    via = _find_via(tech, m4_layer, stub_layer, env.get("PPS_VIA_NAME", ""))
    vinfo = _via_info(tech, via, to_dbu(um("PPS_VIA_CUT_PITCH", 0)))
    clr = to_dbu(um("PPS_M4_CLEARANCE", 0.6))

    # all special-wire shapes by layer
    shapes: Dict[str, List[Shape]] = {}
    for net in block.getNets():
        for sw in net.getSWires():
            for b in sw.getWires():
                if b.isVia():
                    continue
                shapes.setdefault(b.getTechLayer().getName(), []).append(
                    (net.getName(), (b.xMin(), b.yMin(), b.xMax(), b.yMax()))
                )
    tm1, m4s = shapes.get(stub_layer, []), shapes.get(m4_layer, [])

    core = block.getCoreArea()
    cx1, cy1, cx2, cy2 = core.xMin(), core.yMin(), core.xMax(), core.yMax()
    if not clr:  # derive from tech: widest case = full stub-width stripe
        widest = max((r[2] - r[0] for n, r in tm1 if n in (vdd, vss)), default=0)
        clr = max(m4.getSpacing(), m4.getSpacing(widest, to_dbu(um("PPS_VIA_HEIGHT", 10))))

    P = Params(
        vdd=vdd, vss=vss,
        ext=to_dbu(um("PPS_STUB_EXTEND", 2.0)), off=to_dbu(um("PPS_VIA_OFFSET", 3.0)),
        height=to_dbu(um("PPS_VIA_HEIGHT", 10.0)), inset=to_dbu(um("PPS_RING_VIA_INSET", 1.0)),
        clearance=clr, min_width=m4.getWidth(), via=vinfo, mfg=max(1, tech.getManufacturingGrid()),
    )

    rings = {
        "top": [(n, r) for n, r in tm1 if n in (vdd, vss) and r[1] >= cy2
                and r[2] - r[0] >= (cx2 - cx1) // 2 and r[2] - r[0] > r[3] - r[1]],
        "bottom": [(n, r) for n, r in tm1 if n in (vdd, vss) and r[3] <= cy1
                   and r[2] - r[0] >= (cx2 - cx1) // 2 and r[2] - r[0] > r[3] - r[1]],
    }

    regex = re.compile(env.get("PPS_PAD_REGEX", ".*"))
    jobs, errors = [], []
    npads = 0
    for inst in block.getInsts():
        if not regex.search(inst.getMaster().getName()):
            continue
        bb = inst.getBBox()
        pad = (bb.xMin(), bb.yMin(), bb.xMax(), bb.yMax())
        side = "top" if pad[1] >= cy2 else "bottom" if pad[3] <= cy1 else None
        if side is None:
            continue
        npads += 1
        for net, r in tm1:
            if net not in (vdd, vss):
                continue
            sx1, su1, sx2, su2 = flip(side, r)
            px1, pu1, px2, pu2 = flip(side, pad)
            if px1 <= sx1 and sx2 <= px2 and sx2 - sx1 < su2 - su1 and su1 <= pu2 < su2:
                jobs.append((inst.getName(), side, net, r, pad))

    plans = []
    nskipped = 0
    for iname, side, net, r, pad in jobs:
        try:
            plan = plan_stub(side, net, r, pad, rings[side], tm1, m4s, P)
            plans.append((net, plan))
            print(f"[PadPowerStubs] {iname} {side} {net} stub x={r[0]/dbu:.2f}..{r[2]/dbu:.2f}: "
                  f"{plan.kind}; {'; '.join(plan.notes)}")
            if plan.kind == "skipped":
                nskipped += 1
        except PlanError as e:
            errors.append(f"{iname} ({net}, x={r[0]/dbu:.2f}..{r[2]/dbu:.2f}): {e}")
    print(f"[PadPowerStubs] {npads} IO cells on the top/bottom edge, {len(jobs)} stubs, {nskipped} skipped (warnings), {len(errors)} errors")
    if errors:
        for e in errors:
            print("[PadPowerStubs] ERROR " + e)
        return 1

    if not dry:
        layer_of = {"stub": tmx, "m4": m4}
        mk_wire, mk_box = _create("dbSWire", odb), _create("dbSBox", odb)
        rt, st = _enum(odb, "dbWireType", "ROUTED"), _enum(odb, "dbWireShapeType", "STRIPE")
        for net, plan in plans:
            if plan.kind in ("connected", "skipped"):
                continue
            sw = mk_wire(block.findNet(net), rt)
            for key, _n, r in plan.boxes:
                mk_box(sw, layer_of[key], r[0], r[1], r[2], r[3], st)
            for _n, x, y in plan.vias:
                mk_box(sw, via, x, y, st)
    odb.write_db(db, out_odb)
    odb.write_def(block, out_def)
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as exc:  # make failures visible to the step
        print(f"[PadPowerStubs] FATAL {type(exc).__name__}: {exc}")
        rc = 1
    sys.exit(rc)

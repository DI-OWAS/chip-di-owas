"""Pure-Python geometry helpers for the pad-to-ring connection step.

No OpenROAD (odb) imports here so the logic can be unit-tested stand-alone.
All rectangles are (xmin, ymin, xmax, ymax) tuples in database units (ints).
"""

from typing import List, Optional, Sequence, Tuple

Rect = Tuple[int, int, int, int]


def orient_name(orient) -> str:
    """odb returns either a plain string or a dbOrientType-like object."""
    if isinstance(orient, str):
        return orient.upper()
    for attr in ("getString", "name"):
        fn = getattr(orient, attr, None)
        if fn is not None:
            return str(fn() if callable(fn) else fn).upper()
    return str(orient).upper()


def transform_rect(r: Rect, orient, w: int, h: int, ox: int, oy: int) -> Rect:
    """Map a master-local rect into block coordinates.

    (ox, oy) is the lower-left corner of the placed instance bounding box,
    (w, h) the *unrotated* master size. All eight DEF orientations are
    supported. Each maps a master-local point so that the placed bbox has its
    lower-left corner at the origin (before adding ox, oy):

        R0     (x, y) -> (x,     y    )
        R90    (x, y) -> (h - y, x    )
        R180   (x, y) -> (w - x, h - y)
        R270   (x, y) -> (y,     w - x)
        MX     (x, y) -> (x,     h - y)
        MY     (x, y) -> (w - x, y    )
        MXR90  (x, y) -> (y,     x    )
        MYR90  (x, y) -> (h - y, w - x)
    """
    maps = {
        "R0": lambda x, y: (x, y),
        "R90": lambda x, y: (h - y, x),
        "R180": lambda x, y: (w - x, h - y),
        "R270": lambda x, y: (y, w - x),
        "MX": lambda x, y: (x, h - y),
        "MY": lambda x, y: (w - x, y),
        "MXR90": lambda x, y: (y, x),
        "MYR90": lambda x, y: (h - y, w - x),
    }
    o = orient_name(orient)
    if o not in maps:
        raise ValueError(f"unknown orientation: {o}")
    f = maps[o]
    x1, y1, x2, y2 = r
    ax, ay = f(x1, y1)
    bx, by = f(x2, y2)
    return (min(ax, bx) + ox, min(ay, by) + oy,
            max(ax, bx) + ox, max(ay, by) + oy)


def overlaps(a: Rect, b: Rect) -> bool:
    """True if the interiors overlap (touching edges do not count)."""
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def inflate(r: Rect, d: int) -> Rect:
    return (r[0] - d, r[1] - d, r[2] + d, r[3] + d)


def center(r: Rect) -> Tuple[float, float]:
    return ((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)


def classify_edge(inst_rect: Rect, core: Rect) -> Optional[str]:
    """'top' / 'bottom' if the instance sits fully above/below the core area."""
    if inst_rect[1] >= core[3]:
        return "top"
    if inst_rect[3] <= core[1]:
        return "bottom"
    return None


def horizontal_ring_segments_outside_core(
    shapes: Sequence[Rect], core: Rect, edge: str
) -> List[Rect]:
    """Horizontal shapes whose centre lies outside the core on the given edge.

    Core-grid straps on the same layer lie inside the core area and are
    therefore ignored; what remains are the horizontal core-ring segments.
    """
    out = []
    for r in shapes:
        if (r[2] - r[0]) <= (r[3] - r[1]):
            continue
        yc = (r[1] + r[3]) / 2.0
        if edge == "top" and yc > core[3]:
            out.append(r)
        elif edge == "bottom" and yc < core[1]:
            out.append(r)
    return out


def select_ring_segment(
    segments: Sequence[Rect], pin: Rect, min_x_overlap: int
) -> Optional[Rect]:
    """Ring segment sharing enough x-range with the pad pin, nearest in y."""
    best, best_d = None, None
    pyc = center(pin)[1]
    for s in segments:
        ov = min(s[2], pin[2]) - max(s[0], pin[0])
        if ov < min_x_overlap:
            continue
        d = abs(center(s)[1] - pyc)
        if best is None or d < best_d:
            best, best_d = s, d
    return best


def pick_columns(
    x_lo: int,
    x_hi: int,
    width: int,
    y_lo: int,
    y_hi: int,
    blockers: Sequence[Rect],
    spacing: int,
    count: int,
    grid: int,
) -> List[int]:
    """Choose up to `count` x-centres for vertical wires of `width`.

    A column [xc-width/2, xc+width/2] x [y_lo, y_hi] is valid if, inflated
    by `spacing`, it overlaps none of `blockers`. The span [x_lo, x_hi] is
    split into `count` slots and the valid column nearest to each slot centre
    is taken, keeping at least width + 2*spacing between chosen columns.
    """
    half = width // 2
    first = x_lo + half
    last = x_hi - (width - half)
    if last < first or count <= 0:
        return []
    grid = max(grid, 1)
    step = max(grid, (width // 4) // grid * grid or grid)

    def valid(xc: int) -> bool:
        wire = (xc - half, y_lo, xc - half + width, y_hi)
        return not any(overlaps(inflate(b, spacing), wire) for b in blockers)

    cands = []
    xc = (first + grid - 1) // grid * grid
    while xc <= last:
        if valid(xc):
            cands.append(xc)
        xc += step
    if not cands:
        return []

    chosen: List[int] = []
    span = x_hi - x_lo
    for i in range(count):
        target = x_lo + (i + 0.5) * span / count
        for xc in sorted(cands, key=lambda v: abs(v - target)):
            if all(abs(xc - c) >= width + 2 * spacing for c in chosen):
                chosen.append(xc)
                break
    return sorted(chosen)


def via_array_origins(
    region: Rect, via_bbox: Rect, pitch: int, max_vias: int = 400
) -> List[Tuple[int, int]]:
    """Origins for a regular array of vias whose bbox fits inside `region`.

    `via_bbox` is relative to the via origin. The array is centred in the
    region. Returns [] if even one via does not fit.
    """
    vw = via_bbox[2] - via_bbox[0]
    vh = via_bbox[3] - via_bbox[1]
    rw = region[2] - region[0]
    rh = region[3] - region[1]
    if vw > rw or vh > rh:
        return []
    pitch_x = max(pitch, vw)
    pitch_y = max(pitch, vh)
    nx = (rw - vw) // pitch_x + 1
    ny = (rh - vh) // pitch_y + 1
    while nx * ny > max_vias:
        if nx >= ny:
            nx -= 1
        else:
            ny -= 1
    used_w = (nx - 1) * pitch_x + vw
    used_h = (ny - 1) * pitch_y + vh
    start_x = region[0] + (rw - used_w) // 2 - via_bbox[0]
    start_y = region[1] + (rh - used_h) // 2 - via_bbox[1]
    return [
        (start_x + i * pitch_x, start_y + j * pitch_y)
        for i in range(nx)
        for j in range(ny)
    ]

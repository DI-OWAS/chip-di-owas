# librelane_plugin_ihp_padpdn

Step `IHP.PadPDNConnect`: connects IO power pads on the top/bottom die edge to
the horizontal TopMetal1 core-ring segments with vertical Metal4 straps and a
via stack, directly on the pad's Metal4 pin shapes.

## Install

Put the folder `librelane_plugin_ihp_padpdn/` on PYTHONPATH (or into
site-packages). LibreLane auto-imports modules named `librelane_plugin_*`.

    export PYTHONPATH=$PWD:$PYTHONPATH

## Use (config.json)

    {
      "meta": {
        "version": 2,
        "flow": "Classic",
        "substituting_steps": {
          "+OpenROAD.GeneratePDN": "IHP.PadPDNConnect"
        }
      },
      "IHP_PADPDN_PADS": [
        ".*IOPadVdd:vdd",
        ".*IOPadVss:vss"
      ]
    }

Pad spec format: `master_regex:pin[:net]`. Without `:net`, the net on the pad
pin is used (it must be globally connected before this step).

Other variables: IHP_PADPDN_STRAP_LAYER (Metal4), IHP_PADPDN_RING_LAYER
(TopMetal1), IHP_PADPDN_STRAP_WIDTH (3.0 um), IHP_PADPDN_CLEARANCE (0.5 um),
IHP_PADPDN_STRAPS_PER_PAD (2), IHP_PADPDN_EDGES (top,bottom),
IHP_PADPDN_STRICT (true).

## What it does

1. Core area from the block; ring = horizontal swire shapes of the pad's net
   on the ring layer whose centre lies outside the core (core straps inside
   the core are ignored).
2. Pads = instances whose master matches; top/bottom by position vs. core.
3. Pin shapes on Metal4 are transformed by the instance orientation.
4. Straps are placed only in x-columns that keep (min spacing + clearance)
   to every other-net Metal4 shape: PDN swires, pad/macro pins, pad OBS.
5. Via stack from Metal4 up to the ring layer (picked from tech/block vias).

If a pad's target pin is shadowed by another net's Metal4 rail between pin and
ring, the step reports which shapes block it and fails (IHP_PADPDN_STRICT).

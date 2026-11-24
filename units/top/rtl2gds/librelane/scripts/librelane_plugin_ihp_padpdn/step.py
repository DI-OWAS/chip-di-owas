import os
from decimal import Decimal
from typing import List

from librelane.config import Variable
from librelane.steps import Step
from librelane.steps.odb import OdbpyStep


@Step.factory.register()
class PadPDNConnect(OdbpyStep):
    """Connects IO power pads on the top and bottom die edge to the horizontal
    TopMetal1 core-ring segments with vertical Metal4 straps and a via stack.

    Pad locations, core area and ring segments are all read from the
    database; nothing is hard-coded. Straps are only placed in columns
    that keep spacing to every other-net Metal4 shape (core-grid stripes,
    other pad pins, pad-cell obstructions).
    """

    id = "IHP.PadPDNConnect"
    name = "Connect IO Power Pads to Core Ring"

    config_vars = OdbpyStep.config_vars + [
        Variable(
            "IHP_PADPDN_PADS",
            List[str],
            "Pads to connect, each as `master_regex:pin[:net]`. The regex "
            "must match the whole master name. If `net` is omitted, the net "
            "attached to the pad's pin is used (so global connect must have "
            "happened).",
            default=[
                r".*IOPadVdd:vdd",
                r".*IOPadVss:vss",
            ],
        ),
        Variable(
            "IHP_PADPDN_STRAP_LAYER",
            str,
            "Layer of the vertical straps (the layer of the pad pins).",
            default="Metal4",
        ),
        Variable(
            "IHP_PADPDN_RING_LAYER",
            str,
            "Layer of the horizontal core-ring segments.",
            default="TopMetal1",
        ),
        Variable(
            "IHP_PADPDN_STRAP_WIDTH",
            Decimal,
            "Width of each vertical strap.",
            default=Decimal("3.0"),
            units="µm",
        ),
        Variable(
            "IHP_PADPDN_CLEARANCE",
            Decimal,
            "Extra clearance to other-net shapes on the strap layer, on "
            "top of the layer's minimum spacing.",
            default=Decimal("0.5"),
            units="µm",
        ),
        Variable(
            "IHP_PADPDN_STRAPS_PER_PAD",
            int,
            "Number of parallel straps per pad pin.",
            default=2,
        ),
        Variable(
            "IHP_PADPDN_EDGES",
            str,
            "Comma-separated die edges to process (`top`, `bottom`).",
            default="top,bottom",
        ),
        Variable(
            "IHP_PADPDN_STRICT",
            bool,
            "Fail the step if any matching pad cannot be connected.",
            default=True,
        ),
    ]

    def get_script_path(self):
        return os.path.join(os.path.dirname(__file__), "pad_pdn_connect.py")

    def get_command(self) -> List[str]:
        c = self.config
        cmd = super().get_command()
        for spec in c["IHP_PADPDN_PADS"]:
            cmd += ["--pad", spec]
        cmd += [
            "--route-layer", c["IHP_PADPDN_STRAP_LAYER"],
            "--ring-layer", c["IHP_PADPDN_RING_LAYER"],
            "--wire-width", str(c["IHP_PADPDN_STRAP_WIDTH"]),
            "--clearance", str(c["IHP_PADPDN_CLEARANCE"]),
            "--straps", str(c["IHP_PADPDN_STRAPS_PER_PAD"]),
            "--edges", c["IHP_PADPDN_EDGES"],
            "--strict" if c["IHP_PADPDN_STRICT"] else "--no-strict",
        ]
        # the script needs LibreLane's own `reader` module; point it there
        try:
            import librelane

            d = os.path.join(
                os.path.dirname(librelane.__file__), "scripts", "odbpy"
            )
            if os.path.isdir(d):
                cmd += ["--odbpy-dir", d]
        except ImportError:
            pass
        return cmd

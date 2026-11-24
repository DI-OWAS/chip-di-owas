# custom LibreLane step definitions or extensions
#
# Andreas Gruebl, KIP (UH2)

import os
import shutil
import logging

from decimal import Decimal
from typing import List, Optional, Tuple

from librelane.common import Path  # LibreLane's own Path type (not pathlib.Path)
from librelane.config import Variable
from librelane.steps import Step, ViewsUpdate, MetricsUpdate
from librelane.steps.yosys import Synthesis
from librelane.steps.openroad import OpenROADStep
from librelane.state import DesignFormat, State
from librelane.steps.odb import OdbpyStep
from librelane.logging import info
from librelane.steps.common_variables import dpl_variables

from typing import (
    Any,
    Dict,
    List,
    Literal,
    Optional,
    Set,
    Tuple,
    TypeAlias,
    Union,
)
		
log = logging.getLogger(__name__)

#############################################################################################
@Step.factory.register()
class SynthesisWithRenameUnescape(Synthesis):
    """
    Drop-in replacement for the standard Yosys synthesis step that uses a script with
    a single extra Yosys command after synthesis: `rename -unescape`.
    This file should be kept up-to-date with the LibreLane repo, or, better:
    a step should be written, that just adds this command to the original script from the repo.
    """

    id = "Yosys.SynthesisWithRenameUnescape"
    name = "Yosys Synthesis + rename -unescape"

    def get_script_path(self) -> str:
        log.error("Using customized synthesis script with unescaped verilog names")
        return os.path.join(self.config["DESIGN_DIR"], "scripts", "synthesize_unescaped.py")


#############################################################################################
@Step.factory.register()
class MacroPDNStubs(OpenROADStep):
    id = "Custom.MacroPDNStubs"
    name = "Macro PDN Edge Stubs"

    inputs = [DesignFormat.ODB]
    outputs = [DesignFormat.ODB]

    config_vars = OpenROADStep.config_vars + [
        Variable(
            "MACRO_STUB_INSTANCE",
            str,
            "Hierarchical instance name of the macro.",
						default="diowas_top_i/efpga_subsystem_top_inst",
        ),
        Variable(
            "MACRO_STUB_VDD_PIN",
            str,
            "Name of the macro's power pin.",
            default="VDD",
        ),
        Variable(
            "MACRO_STUB_VSS_PIN",
            str,
            "Name of the macro's ground pin.",
            default="VSS",
        ),
        Variable(
            "MACRO_STUB_H_LAYER",
            str,
            "Metal layer of the macro's horizontal power pins. Stubs are drawn on it "
            "at the macro's left and right edges.",
            default="TopMetal1",
        ),
        Variable(
            "MACRO_STUB_V_LAYER",
            str,
            "Metal layer of the macro's vertical power pins. Stubs are drawn on it "
            "at the macro's bottom and top edges.",
            default="Metal4",
        ),
        Variable(
            "MACRO_STUB_LEFT_LENGTH",
            float,
            "Stub length extending away from the macro's left edge. 0 disables the side.",
            default=20.0,
            units="um",
        ),
        Variable(
            "MACRO_STUB_RIGHT_LENGTH",
            float,
            "Stub length extending away from the macro's right edge. 0 disables the side.",
            default=20.0,
            units="um",
        ),
        Variable(
            "MACRO_STUB_BOTTOM_LENGTH",
            float,
            "Stub length extending away from the macro's bottom edge. 0 disables the side.",
            default=28.0,
            units="um",
        ),
        Variable(
            "MACRO_STUB_TOP_LENGTH",
            float,
            "Stub length extending away from the macro's top edge. 0 disables the side.",
            default=28.0,
            units="um",
        ),
        Variable(
            "MACRO_STUB_OVERLAP",
            float,
            "How far a stub reaches into the pin shape, to guarantee shape overlap.",
            default=1.0,
            units="um",
        ),
    ]

    def get_script_path(self):
        return os.path.join(os.path.dirname(__file__), "macro_pdn.tcl")



#############################################################################################
@Step.factory.register()
class ReplaceBlockageWithSoft(Step):
    """
    Deletes a (hard) placement blockage at a given location in the ODB and
    recreates it at the same location as a soft blockage. Intended to run after
    global placement.
    """

    id = "Custom.ReplaceBlockageWithSoft"
    name = "Replace Placement Blockage With Soft Blockage"

    inputs = [DesignFormat.ODB]
    outputs = [DesignFormat.ODB]

    config_vars = [
        Variable(
            "REPLACE_BLOCKAGE_BBOX",
            List[Decimal],
            "Location of the blockage as [x0, y0, x1, y1] in microns.",
            units="um",
        ),
        Variable(
            "REPLACE_BLOCKAGE_TOLERANCE",
            Decimal,
            "Allowed deviation per coordinate when matching the blockage.",
            default=Decimal("0"),
            units="um",
        ),
        Variable(
            "REPLACE_BLOCKAGE_KEEP_DENSITY",
            bool,
            "Copy the max placement density of the old blockage to the new one.",
            default=False,
        ),
    ]

    def run(self, state_in: State, **kwargs) -> Tuple[ViewsUpdate, MetricsUpdate]:
        bbox = self.config["REPLACE_BLOCKAGE_BBOX"]
        if len(bbox) != 4:
            raise ValueError("REPLACE_BLOCKAGE_BBOX must have exactly 4 values.")

        out_odb = os.path.join(self.step_dir, f"{self.config['DESIGN_NAME']}.odb")
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "replace_blockage.py")

        cmd = [
            "openroad", "-exit", "-no_splash", "-python", script,
            "--input", str(state_in[DesignFormat.ODB]),
            "--output", out_odb,
            "--bbox", *[str(v) for v in bbox],
            "--tolerance", str(self.config["REPLACE_BLOCKAGE_TOLERANCE"]),
        ]
        if self.config["REPLACE_BLOCKAGE_KEEP_DENSITY"]:
            cmd.append("--keep-density")

        self.run_subprocess(cmd)

        return {DesignFormat.ODB: Path(out_odb)}, {}



#############################################################################################
@Step.factory.register()
class CustomCTS(OpenROADStep):
    """
    Creates a `Clock tree <https://en.wikipedia.org/wiki/Clock_signal#Distribution>`_
    for an ODB file with detailed-placed cells, using reasonably accurate resistance
    and capacitance estimations. Detailed Placement is then re-performed to
    accommodate the new cells.
    """

    id = "Custom.CustomCTS"
    name = "Clock Tree Synthesis"

    config_vars = (
        OpenROADStep.config_vars
        + dpl_variables
        + [
            # sink_buffer_max_cap_derate
            Variable(
                "CTS_BALANCE_LEVELS",
                Optional[bool],
                "Attempts to keep a similar number of levels in the clock tree across non-register cells (e.g., clock-gate or inverter).",
            ),
            Variable(
                "CTS_SINK_BUFFER_MAX_CAP_DERATE_PCT",
                Optional[Decimal],
                "Controls automatic buffer selection. To favor strong(weak) drive strength buffers use a small(large) value."
                + "The value of 100 means no derating of max cap limit",
                units="%",
            ),
            Variable(
                "CTS_DELAY_BUFFER_DERATE_PCT",
                Optional[Decimal],
                "This option balances latencies between macro cells and registers by inserting delay buffers"
                + "The value of 100 means all needed delay buffers are inserted",
                units="%",
            ),
            Variable(
                "CTS_OBSTRUCTION_AWARE",
                Optional[bool],
                "Enables obstruction-aware buffering such that clock buffers are not placed on top of blockages or hard macros. "
                + "This option may reduce legalizer displacement, leading to better latency, skew or timing QoR.",
            ),
            Variable(
                "CTS_SINK_CLUSTERING_ENABLE",
                bool,
                "Enables pre-clustering of sinks to create one level of sub-tree before building the H-tree. "
                + "Each cluster is driven by a buffer which becomes the end point of the H-tree structure.",
                default=True,
            ),
            Variable(
                "CTS_SINK_CLUSTERING_SIZE",
                Optional[int],
                "Specifies the maximum number of sinks per cluster.",
            ),
            Variable(
                "CTS_SINK_CLUSTERING_MAX_DIAMETER",
                Optional[Decimal],
                "Specifies the maximum diameter of the sink cluster.",
                units="µm",
            ),
            Variable(
                "CTS_MACRO_CLUSTERING_SIZE",
                Optional[int],
                "Specifies the maximum number of sinks per cluster for the macro tree.",
            ),
            Variable(
                "CTS_MACRO_CLUSTERING_MAX_DIAMETER",
                Optional[Decimal],
                "Specifies the maximum diameter of the sink cluster for the macro tree.",
                units="µm",
            ),
            Variable(
                "CTS_CLK_MAX_WIRE_LENGTH",
                Decimal,
                "Specifies the maximum wire length on the clock net.",
                default=0,
                units="µm",
            ),
            Variable(
                "CTS_DISABLE_POST_PROCESSING",
                bool,
                "Specifies whether or not to disable post cts processing for outlier sinks.",
                default=False,
            ),
            Variable(
                "CTS_DISTANCE_BETWEEN_BUFFERS",
                Decimal,
                "Specifies the distance between buffers when creating the clock tree.",
                default=0,
                units="µm",
            ),
            Variable(
                "CTS_CORNERS",
                Optional[List[str]],
                "Clock tree synthesis step-specific override for PNR_CORNERS.",
            ),
            Variable(
                "CTS_ROOT_BUFFER",
                str,
                "Defines the cell inserted at the root of the clock tree. Used in CTS.",
                pdk=True,
            ),
            Variable(
                "CTS_CLK_BUFFERS",
                List[str],
                "Defines the list of clock buffer names or buffer name wildcards to be used in CTS.",
                deprecated_names=["CTS_CLK_BUFFER_LIST"],
                pdk=True,
            ),
            Variable(
                "CTS_MAX_CAP",
                Optional[Decimal],
                "Overrides the maximum capacitance CTS characterization will test. If omitted, the capacitance is extracted from the lib information of the buffers in CTS_CLK_BUFFERS.",
                units="pF",
            ),
            Variable(
                "CTS_MAX_SLEW",
                Optional[Decimal],
                "Overrides the maximum transition time CTS characterization will test. If omitted, the slew is extracted from the lib information of the buffers in CTS_CLK_BUFFERS.",
                units="ns",
            ),
            Variable(
                "CTS_APPLY_NDR",
                Literal["none", "root_only", "half", "full"],
                "Applies 2X spacing non-default rule to clock nets except leaf-level nets following some strategy. There are four strategy options: 'none', 'root_only', 'half', 'full'.",
                default="half",
            ),
            Variable(
                "CTS_NO_INSERTION_DELAY",
                bool,
                "Specifies whether or not to set the flag to ignore sink insertion delay during cts.",
                default=False,
            ),
        ]
    )

    def get_script_path(self):
        return os.path.join(os.path.dirname(os.path.abspath(__file__)), "custom_cts.tcl")

    def run(self, state_in: State, **kwargs) -> Tuple[ViewsUpdate, MetricsUpdate]:
        kwargs, env = self.extract_env(kwargs)
        if self.config.get("CLOCK_NET") is None:
            if clock_port := self.config["CLOCK_PORT"]:
                if isinstance(clock_port, list):
                    env["CLOCK_NET"] = TclUtils.join(clock_port)
                else:
                    env["CLOCK_NET"] = clock_port
            else:
                self.warn(
                    "No CLOCK_NET (or CLOCK_PORT) specified. CTS cannot be performed. Returning state unaltered…"
                )
                return {}, {}

        views_updates, metrics_updates = super().run(
            state_in,
            corners=self.config["CTS_CORNERS"] or self.config["STA_CORNERS"],
            env=env,
            **kwargs,
        )

        return views_updates, metrics_updates



#############################################################################################
@Step.factory.register()
class MacroClockDelay(OdbpyStep):
    """
    After CTS, inserts a chain of buffers directly in front of the clock
    input(s) of every macro matching MACRO_CLK_DELAY_PATTERNS, to delay the
    macro clock and fix hold violations caused by a too-shallow macro clock
    subtree. Works on the macro's own clock pins, so shared subtrees do not
    matter.
    """

    id = "Custom.MacroClockDelay"
    name = "Delay Macro Clock Subtrees"

    config_vars = dpl_variables + [
        Variable(
            "MACRO_CLK_DELAY_PATTERNS",
            List[str],
            "Regular expressions (full match) on macro instance names.",
            default=[],
        ),
        Variable(
            "MACRO_CLK_DELAY_PIN_RX",
            str,
            "Regular expression (full match) on macro pin names that are clock pins, in addition to pins marked USE CLOCK in the LEF.",
            default=".*CLK.*",
        ),
        Variable(
            "MACRO_CLK_DELAY_BUFFER",
            str,
            "Buffer cell to insert.",
            default="sg13cmos5l_buf_2",
        ),
        Variable(
            "MACRO_CLK_DELAY_COUNT",
            int,
            "Number of buffers in series inserted directly in front of the clock input of each macro.",
            default=2,
        ),
        Variable(
            "MACRO_CLK_DELAY_DRY_RUN",
            bool,
            "Only report the macro clock inputs that were found, do not modify the design.",
            default=False,
        ),
    ]

    def get_script_path(self):
        return os.path.join(os.path.dirname(__file__), "macro_clk_delay.py")

    def get_command(self) -> List[str]:
        assert self.config_path is not None, "get_command called before start()"
        return super().get_command() + ["--step-config", self.config_path]

    def run(self, state_in: State, **kwargs) -> Tuple[ViewsUpdate, MetricsUpdate]:
        if not self.config["MACRO_CLK_DELAY_PATTERNS"]:
            info(f"'MACRO_CLK_DELAY_PATTERNS' is empty. Skipping '{self.id}'?")
            return {}, {}
        return super().run(state_in, **kwargs)



#############################################################################################
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pad_power_stubs.py")

@Step.factory.register()
class PadPowerStubs(Step):
    id = "IHP.PadPowerStubs"
    name = "Connect Core Power Pad Stubs to Core Ring"

    inputs = [DesignFormat.ODB]
    outputs = [DesignFormat.ODB, DesignFormat.DEF]

    config_vars = [
        Variable("PAD_POWER_PAD_MASTER_REGEX", str,
                 "Regular expression (re.search) selecting which IO cells on the top/bottom edge "
                 "are considered; the default takes every cell outside the core.",
                 default=".*"),
        Variable("PAD_POWER_VDD_NET", str, "Name of the core power net.", default="VDD"),
        Variable("PAD_POWER_VSS_NET", str, "Name of the core ground net.", default="VSS"),
        Variable("PAD_POWER_STUB_LAYER", str, "Layer of the stubs and of the core ring.",
                 default="TopMetal1"),
        Variable("PAD_POWER_STRIPE_LAYER", str, "Layer of the bridging stripe for VDD.",
                 default="Metal4"),
        Variable("PAD_POWER_STUB_EXTEND", Decimal,
                 "Length by which a stub that directly faces its ring stripe is extended.",
                 default=Decimal("2.0"), units="um"),
        Variable("PAD_POWER_VIA_OFFSET", Decimal,
                 "Distance between the pad's inner edge and the near edge of the stub via array.",
                 default=Decimal("3.0"), units="um"),
        Variable("PAD_POWER_VIA_HEIGHT", Decimal, "Height of the via array on the stub.",
                 default=Decimal("10.0"), units="um"),
        Variable("PAD_POWER_RING_VIA_INSET", Decimal,
                 "Margin between the ring-side via array and the edges of the ring stripe.",
                 default=Decimal("1.0"), units="um"),
        Variable("PAD_POWER_M4_CLEARANCE", Decimal,
                 "Spacing kept to foreign Metal4 stripes (covers wide-metal spacing); 0 derives it "
                 "from the technology.",
                 default=Decimal("0.6"), units="um"),
        Variable("PAD_POWER_VIA_CUT_PITCH", Decimal,
                 "Via cut pitch; 0 derives it from cut size + technology cut spacing.",
                 default=Decimal("0"), units="um"),
        Variable("PAD_POWER_VIA_NAME", str,
                 "Technology via to use; empty selects the simplest via between the two layers.",
                 default=""),
        Variable("PAD_POWER_DRY_RUN", bool,
                 "Only plan and report, do not modify the design.", default=False),
    ]

    def run(self, state_in: State, **kwargs) -> Tuple[ViewsUpdate, MetricsUpdate]:
        openroad = shutil.which("openroad")
        if openroad is None:
            raise RuntimeError("openroad not found in PATH")
        out_odb = os.path.join(self.step_dir, f"{self.config['DESIGN_NAME']}.odb")
        out_def = os.path.join(self.step_dir, f"{self.config['DESIGN_NAME']}.def")
        c = self.config
        env = dict(os.environ)
        env.update({
            "PPS_INPUT_ODB": str(state_in[DesignFormat.ODB]),
            "PPS_OUTPUT_ODB": out_odb,
            "PPS_OUTPUT_DEF": out_def,
            "PPS_PAD_REGEX": c["PAD_POWER_PAD_MASTER_REGEX"],
            "PPS_VDD_NET": c["PAD_POWER_VDD_NET"],
            "PPS_VSS_NET": c["PAD_POWER_VSS_NET"],
            "PPS_STUB_LAYER": c["PAD_POWER_STUB_LAYER"],
            "PPS_STRIPE_LAYER": c["PAD_POWER_STRIPE_LAYER"],
            "PPS_STUB_EXTEND": str(c["PAD_POWER_STUB_EXTEND"]),
            "PPS_VIA_OFFSET": str(c["PAD_POWER_VIA_OFFSET"]),
            "PPS_VIA_HEIGHT": str(c["PAD_POWER_VIA_HEIGHT"]),
            "PPS_RING_VIA_INSET": str(c["PAD_POWER_RING_VIA_INSET"]),
            "PPS_M4_CLEARANCE": str(c["PAD_POWER_M4_CLEARANCE"]),
            "PPS_VIA_CUT_PITCH": str(c["PAD_POWER_VIA_CUT_PITCH"]),
            "PPS_VIA_NAME": c["PAD_POWER_VIA_NAME"],
            "PPS_DRY_RUN": "1" if c["PAD_POWER_DRY_RUN"] else "0",
        })
        self.run_subprocess([openroad, "-exit", "-no_splash", "-python", SCRIPT], env=env)
        if not (os.path.exists(out_odb) and os.path.exists(out_def)):
            raise RuntimeError("PadPowerStubs failed, see the step log")
        return {DesignFormat.ODB: Path(out_odb), DesignFormat.DEF: Path(out_def)}, {}

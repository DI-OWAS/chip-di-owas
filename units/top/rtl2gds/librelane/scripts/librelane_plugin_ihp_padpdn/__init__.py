"""LibreLane plugin: connect IO power pads to the TopMetal1 core ring (IHP).

Importing this package registers the step `IHP.PadPDNConnect`.
LibreLane auto-imports top-level modules named `librelane_plugin_*` found
on PYTHONPATH or in site-packages.
"""

from .step import PadPDNConnect

__all__ = ["PadPDNConnect"]

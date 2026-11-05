<!--
SPDX-FileCopyrightText: 2026 DI-OWAS team
SPDX-License-Identifier: Apache-2.0
-->

# Octal PSRAM test

Tests the 4 octal PSRAM chips (APS12808L, 64 MB at `0x20000000`):
* CPU word/half/byte accesses and byte-lane isolation
* crypto DMA copies SRAM1 <-> PSRAM and PSRAM -> PSRAM (burst lengths, 4 KB crossings)
* CPU and DMA on the PSRAM at the same time
* AES-CTR encrypt/decrypt round trip

Prints `TEST PASS` / `TEST FAIL` (UART `19200-8-N-1`). The board build loops forever.

How to build:

```
$ make exe          # board, runs from SRAM0
$ make exec_image   # board, runs from the PSRAM
$ make sim_image    # system TB image (octram_boot_image.mem, one pass)
```

`OCTRAM_CHIP_MB=8` for 64 Mbit chips (default 16).

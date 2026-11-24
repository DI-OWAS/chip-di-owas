# DI-OWAS Bootloader

Features:
* minimal CPU initialization
* initialize UART (`19200-8-N-1`)
* initialize PSRAM controller (at slowest speed)
* wait for executable sent via UART (in raw byte-mode, no protocol)
* note that the excutable requires the default AIRISC file header (signature, size, checksum)

How to recompile:

```
$ make clean bl_image
```


# DC Vision Systems CNN Accelerator Reference Model

## Overview

C++17 software reference model for neural-network inference, used as a correctness and profiling baseline for future RTL/FPGA/ASIC acceleration (DI-OWAS).

Supported workloads:

- **Object detection** — YOLO (e.g. YOLOv4-Tiny)
- **Image classification** — TensorFlow-exported ConvNet graphs
- **Monocular depth estimation** — Depth Anything V2 (ViT-S / DINOv2 encoder + DPT-style decoder, 196×196)

Topologies are described in YOLO-style `.cfg` files. The same modular `DC_Layer` pipeline builds CNN graphs and expanded Vision Transformer graphs (hundreds of layers for Depth Anything).

## Project Context

Core software component of DI-OWAS. The compute API and tensor I/O contract are kept consistent across accelerated layers so the same software behavior can be mapped to hardware while preserving correctness.

## Motivation

Modern vision models are no longer convolution-only. Accelerators must be scoped against both CNN detection/classification and transformer-based depth networks (attention, GEMM, LayerNorm, multi-tensor residual graphs). This reference model runs an unoptimized inference path, collects per-layer compute/memory statistics, and provides format-specific visualization so hardware work can target real bottlenecks.

## Features

- **C++17**, CMake build, Windows / Linux (optional RISC-V and BareMetal targets via `TARGET_OS` / `TARGET_ARCH`)
- **Self-contained inference** — no external ML frameworks; image I/O via vendored `stb_image` under `third_party/`
- **Multiple weight formats**: `"yolo"`, `"tensorflow"`, `"depth_anything"`
- **Per-layer performance statistics** (MACs, arithmetic ops, memory accesses, timing)
- **Hardware-oriented design**: unified compute kernels, explicit HWC/CHW memory order, deterministic execution for co-sim

### Supported layers

| Category | Layers |
|----------|--------|
| CNN / YOLO | Conv2D, DeConv2D, MaxPool2D, AvgPool2D, Dense, Flatten, Upsample, Resize, Softmax, SoftmaxND, YOLO, Route, Shortcut, L2Norm |
| Transformer / Depth Anything | Gemm, MatMul, LayerNorm, SkipLayerNorm, Gather, Slice, Reshape, Transpose, Concat, Add, Mul, Gelu, Relu |

### Ready-to-run configs

| Config | Task |
|--------|------|
| `cnn_net_configs/dc_yolo.json` | YOLOv4-Tiny detection |
| `cnn_net_configs/dc_tensorflow.json` | TensorFlow ConvNet classification |
| `cnn_net_configs/depth_anything.json` | Depth Anything V2-S depth estimation |

## Usage

### Build

```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

Optional CMake cache variables:

- `TARGET_OS` — `Window` (default on Windows hosts), `Linux`, `BareMetal`
- `TARGET_ARCH` — `x86_64` (default), `riscv_32`

### Run inference

```bash
net.exe <cnn_config_file_path>
```

Example:

```bash
net.exe ../cnn_net_configs/depth_anything.json
```

JSON config fields:

```json
{
  "network_topology_file": ".../network.cfg",
  "weights_file": ".../network.weights",
  "image_inputs_dir": ".../images",
  "weight_format": "yolo | tensorflow | depth_anything"
}
```

`weight_format` selects weight loading and post-processing:

| Format | Output layer | Visualization |
|--------|--------------|---------------|
| `yolo` | YOLO | Bounding boxes on annotated images |
| `tensorflow` | Softmax | Classification confidence scores |
| `depth_anything` | Gather | Depth maps as `depth_<id>.png` (min–max normalized) |

## Input / Output

### Inputs

- **Images**: PNG, JPG (directory scanned by `DC_ImageUtils::get_images`)
- **Topology**: YOLO-style `.cfg` (including Depth Anything graphs exported/expanded from ONNX-style architectures)
- **Weights**:
  - Darknet YOLO binaries
  - TensorFlow-exported ConvNet binaries
  - Depth Anything sequential weight binaries for `depth_anything`

### Outputs

- Task-specific visualizations (detections / class scores / depth PNGs)
- Per-layer statistics report via `DC_PerformanceStats`

## Software Architecture

```
DC Vision Systems CNN Framework
├── Core Network (DC_CNN_Network)
│   └── Forward propagation (execute_classification_task)
│
├── Layers (include/modules/layers, src/modules/layers)
│   ├── DC_layer (base)
│   └── DC_CNNLayer_* (Conv2D, MaxPool2D, Dense, YOLO, Route,
│       Gemm, MatMul, LayerNorm, Gather, … — flat, one class per file)
│
├── Utilities (include/modules/utils, src/modules/utils)
│   ├── DC_config_parser / DC_network_builder
│   ├── DC_weight_loader (YOLO / TensorFlow / Depth Anything)
│   ├── DC_image_utils
│   ├── DC_yolo_utils / DC_depth_utils
│   └── DC_PerformanceStats
│
└── Interface
    └── C++ CLI (net.exe) + library (net_lib)
```

Pipeline:

1. Parse JSON config (`parse_json_config`)
2. Build layer graph from `.cfg` and load weights (`build_cnn_layers_from_config`)
3. Run forward pass (`execute_classification_task`)
4. Visualize by format (`visualize_cnn_outputs`) and print stats (`generateReport`)

### Hardware accelerator reference

- **Primary accelerated layer set**: Conv2D, MaxPool2D, Dense, Route, Upsample (unified compute API / DMA-friendly tensors)
- **Extended software layers** (transformer/depth path) provide reference behavior and statistics for future accelerator scoping
- **Data movement**: contiguous tensors with explicit HWC/CHW layout
- **Validation**: per-layer reference fixtures under `test_data/` (including Depth Anything layer checks)

## License

Licensed under the Apache License, Version 2.0. See `LICENSE` for details.

For API-level documentation, see Doxygen output under `docs/` when generated.

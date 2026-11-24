# OWAS Chip

## Cloning this Repository

This repository uses git submodules for tracking externally-developed repositories.
To directly acquire all required submodules, please use the `--recurse-submodules` option when cloning:

```
git clone --recurse-submodules URL
```

Alternatively, use the `git submodule` sub-commands (`init` and `update`) to download all required submodules after the initial clone.

## Build Environment

The build environment is encapsulated into a single [Apptainer](https://apptainer.org/) container image.

### Apptainer Installation

An apptainer installation guide is available here:
https://apptainer.org/docs/admin/latest/installation.html

### Container Image

The latest image is available for download [here](https://openproject.bioai.eu/containers/owas/stable) (e.g., `2025-12-29_1.img`).

If you want to build it yourself, please have a look at the content of [`env/container`](env/container).

## Running the full flow

Here, we assume the downloaded container image to be located at `$PWD/owas.img`.

```shell
TERM=xterm OWAS_CONTAINER=$PWD/owas.img make
```

Please check the [collection of common problems](doc/CommonProblems.md) in case you encounter any issue upon execution.

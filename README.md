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

See [container-di-owas](https://github.com/di-owas/container-di-owas).

## Running the full flow

Here, we assume the downloaded container image to be located at `$PWD/owas.img`.

```shell
TERM=xterm OWAS_CONTAINER=$PWD/owas.img make
```

Please check the [collection of common problems](doc/CommonProblems.md) in case you encounter any issue upon execution.

# Acknowledgements

The project underlying this repository was funded by the German
"Bundesministeriums für Forschung, Technologie und Raumfahrt" under grant
numbers 16ME0963K and 16ME0964. Responsibility for the content of this
publication lies with the contributors.

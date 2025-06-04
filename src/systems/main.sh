#!/bin/bash
# The files in this directory include templates and convenience functions for working with common subject systems.
# Most functions extract (an excerpt of) the tagged history of a kconfig model.
# For customizations (e.g., extract one specific revision or weekly revisions), copy the code to your experiment file and adjust it.

# systems to include
SYSTEMS=(
    axtls
    buildroot
    busybox
    embtoolkit
    fiasco
    file
    freetz-ng
    linux
    toybox
    uclibc-ng
    testsystem
)

for system in "${SYSTEMS[@]}"; do
    source-script "$SRC_DIRECTORY/systems/$system.sh"
done
#!/bin/bash
# The files in this directory include templates and convenience functions for working with common experiment subjects.
# Most functions extract (an excerpt of) the tagged history of a kconfig model.
# For customizations (e.g., extract one specific revision or weekly revisions), copy the code to your experiment file and adjust it.

# scripts to include
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
    source-script "$SCRIPTS_DIRECTORY/subjects/$system.sh"
done

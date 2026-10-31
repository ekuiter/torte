#!/bin/bash
directory=$(dirname "$0")
temporary_directory=$(mktemp -d)
trap 'rm -r -- "$temporary_directory"' EXIT
"$directory/sharpSAT" \
    -decot 120 \
    -decow 100 \
    -tmpdir "$temporary_directory" \
    "$1"

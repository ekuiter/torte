#!/bin/bash
directory=$(dirname "$0")
LD_LIBRARY_PATH="$directory/lib" \
    "$directory/d4" -i "$1" -m counting

#!/bin/bash

directory=$(dirname "$0")
temporary_directory=$(mktemp -d)
trap 'rm -r -- "$temporary_directory"' EXIT

temporary_cnf=$temporary_directory/input.cnf
proof=$temporary_directory/proof.out

"$directory/26-satsuma" fix "$1" \
    --silent \
    --full-skip-limit 100000000 \
    --add-reduced-as-unit \
    --bsr \
    --proof-file "$proof" \
    --out-file "$temporary_cnf" \
    || exit
"$directory/26-kissat" "$temporary_cnf" "$proof"

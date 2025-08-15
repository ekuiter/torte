#!/bin/bash
"$(dirname "$0")"/sharpSAT -decot 120 -decow 100 -tmpdir "$(mktemp -d)" "$1"
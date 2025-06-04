#!/bin/bash

SBVA="$(dirname "$0")"/23-bva
SOLVER="$(dirname "$0")"/23-cadical

OUTER_TIMEOUT=400
INNER_TIMEOUT=200

python3 "$(dirname "$0")"/23-wrapper.py \
    --input $1 \
    --output "$(mktemp)" \
    --bva $SBVA \
    --t1 $INNER_TIMEOUT \
    --t2 $OUTER_TIMEOUT \
    --solver $SOLVER

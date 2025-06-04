#!/bin/bash

SOLVER="$(dirname "$0")"/abcdsat-2015
yes '' | "$SOLVER" "$1"
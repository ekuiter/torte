#!/bin/bash
# ./extract-kconfig.sh
# compiles kconfig bindings and extracts kconfig models using kclause

# shellcheck source=../../scripts/main.sh
source main.sh load-config
register-kconfig-extractor kclause kextractor
load-subjects
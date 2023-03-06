#!/bin/bash
# ./extract-kconfig.sh
# compiles kconfig bindings and extracts kconfig models using kconfigreader

# shellcheck source=../../scripts/main.sh
source main.sh load-config
register-kconfig-extractor kconfigreader dumpconf
load-subjects
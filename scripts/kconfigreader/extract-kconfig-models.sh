#!/bin/bash
# ./extract-kconfig-models.sh
# compiles kconfig bindings and extracts kconfig models using kconfigreader

# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
register-kconfig-extractor kconfigreader dumpconf
load-subjects
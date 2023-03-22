#!/bin/bash
# ./extract-kconfig-models.sh
# compiles kconfig bindings and extracts kconfig models using kconfigreader

load-config
register-kconfig-extractor kconfigreader dumpconf
load-subjects
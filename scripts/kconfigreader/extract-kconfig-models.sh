#!/bin/bash
# ./extract-kconfig-models.sh
# reads kconfig models into .model files using kconfigreader

add-kconfig-model() {
    local system=$1
    local revision=$2
    local c_binding_files=$3
    local kconfig_file=$4
    local env=$5
    require-value system revision c_binding_files kconfig_file
    compile-c-binding-and-extract-kconfig-model kconfigreader dumpconf \
        $system $revision $c_binding_files $kconfig_file $env
}

source main.sh init
echo system,tag,c-binding,kconfig-file > $(output-csv)
source main.sh load
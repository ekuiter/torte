#!/bin/bash
# ./extract-kconfig.sh
# compiles kconfig bindings and extracts kconfig models using kclause

# todo: reduce code duplication with kconfigreader?

add-kconfig-binding() {
    local system=$1
    local revision=$2
    local kconfig_binding_files_spec=$3
    require-value system revision kconfig_binding_files_spec
    kconfig-checkout $system $revision $kconfig_binding_files_spec
    compile-kconfig-binding kextractor $system $revision $kconfig_binding_files_spec
}

add-kconfig-model() {
    local system=$1
    local revision=$2
    local kconfig_binding_file=$3
    local kconfig_file=$4
    local env=$5
    require-value system revision kconfig_file
    kconfig-checkout $system $revision
    extract-kconfig-model kclause kextractor \
        $system $revision $kconfig_binding_file $kconfig_file $env
}

add-kconfig() {
    local system=$1
    local revision=$2
    local kconfig_binding_files_spec=$3
    local kconfig_file=$4
    local env=$5
    require-value system revision kconfig_binding_files_spec kconfig_file
    kconfig-checkout $system $revision $kconfig_binding_files_spec
    compile-kconfig-binding kextractor $system $revision $kconfig_binding_files_spec
    extract-kconfig-model kclause kextractor \
        $system $revision "" $kconfig_file $env
}

source main.sh load-config
echo system,tag,kconfig-binding,kconfig-file > $(output-csv)
source main.sh load-subjects
#!/bin/bash
kconfig_binding_file=$1
kclause_file=$2
features_file=$3
args=("${@:4}")
"$kconfig_binding_file" --extract -o "$kclause_file" "${args[@]}"
"$kconfig_binding_file" --configs "${args[@]}" > "$features_file"
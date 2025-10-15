#!/bin/bash
lkc_binding_file=$1
kclause_file=$2
features_file=$3
kconfig_file=$4
"$lkc_binding_file" --extract -o "$kclause_file" "$kconfig_file" >&2
"$lkc_binding_file" --configs "$kconfig_file" > "$features_file"
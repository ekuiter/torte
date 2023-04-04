#!/bin/bash
kclause_file=$1
kconfig_model=$2
kclause < "$kclause_file" > "$kconfig_model"
kconfig_model_tmp=$(mktemp)
python3 /home/kclause2model.py "$kconfig_model" > "$kconfig_model_tmp" && mv "$kconfig_model_tmp" "$kconfig_model"
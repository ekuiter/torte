#!/bin/bash
kextractor_file=$1
kclause_file=$2
kconfig_model=$3
kclause < "$kextractor_file" > "$kclause_file"
python3 /home/kclause2model.py "$kclause_file" > "$kconfig_model"
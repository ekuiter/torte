#!/bin/bash
kextractor_file=$1
kclause_file=$2
kconfig_model=$3

# extract model as pickled file
kclause < "$kextractor_file" > "$kclause_file"

# transform model into kconfigreader format
python3 /home/kclause2model.py "$kclause_file" > "$kconfig_model"

# remove CONFIG_ prefix to save space
sed -i s/\(CONFIG_/\(/g "$kconfig_model"
#!/bin/bash
set -e

model_file="$1"

if [[ -z $model_file ]]; then
    echo "Usage: $0 <model_file>"
    exit 1
fi

sed -i'' 's/definedEx(/def(/g' "$model_file"
sed -i'' 's/ || /|/g' "$model_file"
sed -i'' 's/ && /\&/g' "$model_file"
#!/bin/bash
# ./transform-into-dimacs.sh
# transforms kconfig models into conjunctive normal form (DIMACS)

load-config
timeout=$2
require-value timeout

echo "model-file,dimacs-file,dimacs-transformation" > "$(output-csv)"
while read -r file; do
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" .model).dimacs
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    subject="ModelToDIMACSKConfigReader: $file"
    log "$subject" "$(echo-progress transform)"
    measure-time "$timeout" \
        /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "$input" "$output"
    if ! is-file-empty "$output"; then
        log "$subject" "$(echo-done)"
    else
        log "$subject" "$(echo-fail)"
        new_file=NA
    fi
    echo "$file,$new_file,ModelToDIMACSKConfigReader" >> "$(output-csv)"
done < <(table-field "$(input-csv)" kconfig-model-file)

#!/bin/bash
# ./transform-into-dimacs.sh
# transforms kconfig models into conjunctive normal form (DIMACS)

# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
timeout=$1
require-value timeout

echo "model-file,dimacs-file,dimacs-transformation" > "$(output-csv)"
while read -r file; do
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" .model).dimacs
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    subject="ModelToDIMACSKConfigReader: $file"
    log "$subject" "$(yellow-color)transform"
    measure-time "$timeout" \
        /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "$input" "$output"
    if ! is-file-empty "$output"; then
        log "$subject" "$(green-color)done"
    else
        log "$subject" "$(red-color)fail"
        new_file=NA
    fi
    echo "$file,$new_file,ModelToDIMACSKConfigReader" >> "$(output-csv)"
done < <(table-field "$(input-csv)" kconfig-model-file)

#!/bin/bash
# ./transform-into-cnf.sh
# transforms kconfig models into conjunctive normal form (DIMACS)

# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
timeout=$1
require-value timeout

echo "kconfig-model,dimacs-file,transformation" > "$(output-csv)"
# todo: how to best load z3?
while read -r file; do
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" .model).dimacs
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    measure-time "$timeout" \
        /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoCNF "$input" "$output"
    if is-file-empty "$output"; then
        new_file=NA
    fi
    echo "$file,$new_file,ModelToDIMACSKConfigReader" >> "$(output-csv)"
done < <(table-field "$(input-csv)" kconfig-model)
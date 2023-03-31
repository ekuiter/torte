#!/bin/bash
# ./transform-into-dimacs.sh
# transforms Boolean SMT files into conjunctive normal form (DIMACS)

timeout=$2
require-value timeout

echo "smt-file,dimacs-file,dimacs-transformation" > "$(output-csv)"
while read -r file; do
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" .smt).dimacs
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    subject="SMTToDIMACSZ3: $file"
    log "$subject" "$(echo-progress transform)"
    measure-time "$timeout" \
        python3 smt2dimacs.py "$input" "$output"
    if ! is-file-empty "$output"; then
        log "$subject" "$(echo-done)"
    else
        log "$subject" "$(echo-fail)"
        new_file=NA
    fi
    echo "$file,$new_file,SMTToDIMACSZ3" >> "$(output-csv)"
done < <(table-field "$(input-csv)" smt-file)
#!/bin/bash

# transforms a file from one file format into another
# measures the transformation time
transform-file(file, input_extension, output_extension, transformer_name, transformer, timeout) {
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    compile-lambda transformer "$transformer"
    log "$transformer_name: $file" "$(echo-progress transform)"
    # shellcheck disable=SC2046
    measure-time "$timeout" $(transformer "$input" "$output") # todo: save time in CSV
    if ! is-file-empty "$output"; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        new_file=NA
    fi
    echo "$file,$new_file,$transformer_name" >> "$(output-csv)"
}

# transforms a list of files from one file format into another
transform-files(csv_file, input_extension, output_extension, transformer_name, transformer, timeout) {
    echo "$input_extension-file,$output_extension-file,$output_extension-transformer" > "$(output-csv)"
    while read -r file; do
        transform-file "$file" "$input_extension" "$output_extension" "$transformer_name" "$transformer" "$timeout"
    done < <(table-field "$csv_file" "$input_extension-file") # todo: ignore NA values
}

# transforms files into various formats using FeatJAR
transform-featjar(input_extension, output_extension, transformer, timeout) {
    local jar=/home/FeatJAR/transform/build/libs/transform-0.1.0-SNAPSHOT-all.jar
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        "$transformer" \
        "$(lambda input,output echo java \
            `# setting a lower memory limit is necessary to avoid that the process is killed erroneously` \
            "-Xmx$(memory-limit 1)G" \
            -jar "$jar" \
            --command transform \
            --timeout "${timeout}000" \
            --input "\$input" \
            --output "\$output" \
            --transformation "${transformer//_/}")" \
        "$timeout"
}

# transforms kconfigreader model files into DIMACS using kconfigreader
transform-kconfigreader(input_extension, output_extension, timeout) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        model_to_dimacs_kconfigreader \
        "$(lambda input,output echo /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "\$input" "\$output")" \
        "$timeout"
}

# transforms SMT files into DIMACS using Z3
transform-z3(input_extension, output_extension, timeout) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        smt_to_dimacs_z3 \
        "$(lambda input,output echo python3 smt2dimacs.py "\$input" "\$output")" \
        "$timeout"
}
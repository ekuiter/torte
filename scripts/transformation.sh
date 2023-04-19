#!/bin/bash

# transforms a file from one file format into another
# measures the transformation time
transform-file(file, input_extension, output_extension, transformer_name, transformer, data_fields=, data_extractor=, timeout=0) {
    local input
    input="$(input-directory)/$file"
    local new_file
    new_file=$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension
    local output
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    compile-lambda transformer "$transformer"
    local output_log
    output_log=$(mktemp)
    log "$transformer_name: $file" "$(echo-progress transform)"
    # shellcheck disable=SC2046
    evaluate "$timeout" $(transformer "$input" "$output") | tee "$output_log"
    if ! is-file-empty "$output"; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        new_file=NA
    fi
    echo -n "$file,${new_file#./},$transformer_name,$(grep -oP "^evaluate_time=\K.*" < "$output_log")" >> "$(output-csv)"
    if [[ -n $data_extractor ]]; then
        if ! is-file-empty "$output"; then
            compile-lambda data-extractor "$data_extractor"
            echo ",$(data-extractor "$output" "$output_log")" >> "$(output-csv)"
        else
            for _ in $(seq 1 $(($(echo "$data_fields" | tr -cd , | wc -c)+1))); do
                echo -n ",NA" >> "$(output-csv)"
            done
            echo >> "$(output-csv)"
        fi
    else
        echo >> "$(output-csv)"
    fi
    rm-safe "$output_log"
}

# transforms a list of files from one file format into another
transform-files(csv_file, input_extension, output_extension, transformer_name, transformer, data_fields=, data_extractor=, timeout=0) {
    echo -n "$input_extension-file,$output_extension-file,$output_extension-transformer,$output_extension-time" > "$(output-csv)"
    if [[ -n $data_fields ]]; then
        echo ",$data_fields" >> "$(output-csv)"
    else
        echo >> "$(output-csv)"
    fi
    while read -r file; do
        transform-file "$file" "$input_extension" "$output_extension" "$transformer_name" "$transformer" "$data_fields" "$data_extractor" "$timeout"
    done < <(table-field "$csv_file" "$input_extension-file" | grep -v ^NA$)
}

# returns additional data fields for DIMACS files
dimacs-data-fields() {
    echo dimacs-variables,dimacs-literals
}

# returns a data extractor lambda for DIMACS files
dimacs-data-extractor() {
    lambda output,output_log echo '$(grep -E ^p < "$output" | cut -d" " -f3),$(grep -E "^[^pc]" < "$output" | grep -Fo " " | wc -l)'
}

# transforms files into various formats using FeatJAR
transform-with-featjar(input_extension, output_extension, transformer, timeout=0, data_fields=, data_extractor=) {
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
        "$data_fields" \
        "$data_extractor" \
        "$timeout"
}

# transforms files into DIMACS using FeatJAR
transform-into-dimacs-with-featjar(input_extension, output_extension, transformer, timeout=0) {
    transform-with-featjar \
        --data-fields "$(dimacs-data-fields)" \
        --data-extractor "$(dimacs-data-extractor)" \
        --input-extension "$input_extension" \
        --input-extension "$input_extension" \
        --output-extension "$output_extension" \
        --transformer "$transformer" \
        --timeout "$timeout"
}

# transforms kconfigreader model files into DIMACS using kconfigreader
transform-into-dimacs-with-kconfigreader(input_extension=model, output_extension=dimacs, timeout=0) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        model_to_dimacs_kconfigreader \
        "$(lambda input,output 'echo /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout"
}

# transforms SMT files into DIMACS using Z3
transform-into-dimacs-with-z3(input_extension=smt, output_extension=dimacs, timeout=0) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        smt_to_dimacs_z3 \
        "$(lambda input,output 'echo python3 smt2dimacs.py "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout"
    # todo: for DIMACS, some solvers require that "c " lines occur before "p cnf", fix that
}

# displays community structure of a DIMACS file with SATGraf
transform-with-satgraf(input_extension=dimacs, output_extension=jpg, timeout=0) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        dimacs_to_jpg_satgraf \
        "$(lambda input,output 'echo ./satgraf.sh "$input" "$output"')" \
        satgraf-modularity \
        "$(lambda output,output_log 'grep -v ^evaluate_ < "$output_log"')" \
        "$timeout"
}
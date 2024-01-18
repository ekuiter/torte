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
    local csv_line=""
    csv_line+="$file,${new_file#./},$transformer_name,$(grep -oP "^evaluate_time=\K.*" < "$output_log")"
    if [[ -n $data_extractor ]]; then
        if ! is-file-empty "$output"; then
            compile-lambda data-extractor "$data_extractor"
            csv_line+=",$(data-extractor "$output" "$output_log")"
        else
            for _ in $(seq 1 $(($(echo "$data_fields" | tr -cd , | wc -c)+1))); do
                csv_line+=",NA"
            done
        fi
    fi
    # technically, this write is unsafe when using parallel jobs.
    # however, as long as the line is not too long, the write buffer saves us.
    # see https://unix.stackexchange.com/q/42544/
    echo "$csv_line" >> "$(output-csv)"
    rm-safe "$output_log"
}

nums(arguments...) {
    echo "${arguments[*]}"
    echo "${#arguments[@]}"
}

# transforms a list of files from one file format into another
transform-files(csv_file, input_extension, output_extension, transformer_name, transformer, data_fields=, data_extractor=, timeout=0, jobs=1) {
    require-command parallel
    echo -n "$input_extension-file,$output_extension-file,$output_extension-transformer,$output_extension-time" > "$(output-csv)"
    if [[ -n $data_fields ]]; then
        echo ",$data_fields" >> "$(output-csv)"
    else
        echo >> "$(output-csv)"
    fi
    table-field "$csv_file" "$input_extension-file" | grep -v NA$ | sort -V \
        | parallel -q ${jobs:+"-j$jobs"} "$SCRIPTS_DIRECTORY/$TOOL.sh" \
        transform-file "{}" "$input_extension" "$output_extension" "$transformer_name" "$transformer" "$data_fields" "$data_extractor" "$timeout"
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
transform-with-featjar(input_extension, output_extension, transformer, timeout=0, data_fields=, data_extractor=, jobs=1) {
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
        "$timeout" \
        "$jobs"
}

# transforms files into DIMACS using FeatJAR
transform-into-dimacs-with-featjar(input_extension, output_extension, transformer, timeout=0, jobs=1) {
    transform-with-featjar \
        --data-fields "$(dimacs-data-fields)" \
        --data-extractor "$(dimacs-data-extractor)" \
        --input-extension "$input_extension" \
        --input-extension "$input_extension" \
        --output-extension "$output_extension" \
        --transformer "$transformer" \
        --timeout "$timeout" \
        --jobs "$jobs"
}

# transforms kconfigreader model files into DIMACS using kconfigreader
transform-into-dimacs-with-kconfigreader(input_extension=model, output_extension=dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        model_to_dimacs_kconfigreader \
        "$(lambda input,output 'echo /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout" \
        "$jobs"
}

# transforms SMT files into DIMACS using Z3
transform-into-dimacs-with-z3(input_extension=smt, output_extension=dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        smt_to_dimacs_z3 \
        "$(lambda input,output 'echo python3 smt2dimacs.py "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout" \
        "$jobs"
}

# displays community structure of a DIMACS file with SATGraf
transform-with-satgraf(input_extension=dimacs, output_extension=jpg, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        dimacs_to_jpg_satgraf \
        "$(lambda input,output 'echo ./satgraf.sh "$input" "$output"')" \
        satgraf-modularity \
        "$(lambda output,output_log 'grep -v ^evaluate_ < "$output_log"')" \
        "$timeout" \
        "$jobs"
}

# computes backbone of a DIMACS file
transform-into-backbone-dimacs-with-kissat(input_extension=dimacs, output_extension=backbone.dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        dimacs_to_backbone_dimacs_kissat \
        "$(lambda input,output 'echo python3 other/backbone_kissat.py --input "$input" --backbone "$(basename "$output" .dimacs).backbone" --output "$output"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}

# for model files, computes all features that are unconstrained and not mentioned in the formula
compute-unconstrained-features(input, output) {
    if [[ -f "$input" ]]; then
        local tmp
        tmp=$(mktemp)
        sed "s/)/)\n/g" < "$input" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq > "$tmp"
        local kextractor_file
        kextractor_file="$(dirname "$input")/$(basename "$input" .model).kextractor"
        if [[ -f $kextractor_file ]]; then
             diff "$tmp" <(grep -E "^config " "$kextractor_file" | cut -d' ' -f2 | sed 's/^CONFIG_//' | sort | uniq) | grep '>' | cut -d' ' -f2 > "$output"
        else
             diff "$tmp" <(grep -E "^#item " "$input" | cut -d' ' -f2 | sort | uniq) | grep '>' | cut -d' ' -f2 > "$output"
        fi
        rm-safe "$tmp"
    fi
}

# transforms models into their unconstrained features
transform-into-unconstrained-features(input_extension=model, output_extension=unconstrained.features, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        model_to_unconstrained_features \
        "$(lambda input,output 'echo '"$SCRIPTS_DIRECTORY/$TOOL.sh"' compute-unconstrained-features "$input" "$output"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}

# extracts core or dead features from a backbone dimacs file (excludes Z3's Tseitin variables for efficiency)
# prefix= extracts core features, prefix=- extracts dead features
compute-core-or-dead-features(input, output, prefix=) {
    grep -E '^'"$prefix"'([^- ]+) 0$' "$input" \
        | cut -d' ' -f1 \
        | sed 's/-//' \
        | sort | uniq \
        | tr '\n' '|' \
        | sed 's/|$//' \
        | awk '{print "^c (" $0 ") ([^ ]+)$"}' \
        | grep -E -f - <(grep c "$input" | grep -v k!) \
        | cut -d ' ' -f3 \
        | sort | uniq
    # binary-search based sgrep implementation, unfortunately this is less efficient than the above
    # local tmp
    # tmp=$(mktemp)
    # echo > "$tmp"
    # grep -E '^c' "$input" | grep -v k! | cut -d' ' -f2- | sort -f >> "$tmp"
    # echo >> "$tmp"
    # grep -E '^'"$prefix"'([^- ]+) 0$' "$input" \
    #     | cut -d' ' -f1 \
    #     | sed 's/-//' \
    #     | while read -r index; do
    #     local variable
    #     variable="$(sgrep '"\n'"$index"' ".."\n"' "$tmp" | grep -vE '^$' | cut -d' ' -f2)"
    #     if [[ -n $variable ]]; then
    #         echo "$variable"
    #     fi
    # done
    # rm-safe "$tmp"
}

# extracts all backbone features from a backbone dimacs file
compute-backbone-features(input, output, prefix=) {
    compute-core-or-dead-features "$input" "$output" '' | awk '{print "+" $0}' > "$output"
    compute-core-or-dead-features "$input" "$output" '-' | awk '{print "-" $0}' >> "$output"
}

# transforms models into their unconstrained features
transform-into-backbone-features(input_extension=backbone.dimacs, output_extension=backbone.features, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        dimacs_to_backbone_features \
        "$(lambda input,output 'echo '"$SCRIPTS_DIRECTORY/$TOOL.sh"' compute-backbone-features "$input" "$output"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}
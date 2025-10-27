#!/bin/bash
# transforms files

# transforms a file from one file format to another
# measures the transformation time
transform-file(file, input_extension, output_extension, transformer_name, transformer, data_fields=, data_extractor=, timeout=0) {
    local new_file input output output_log csv_line
    new_file=$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension
    input="$(input-directory)/$file"
    output="$(output-directory)/$new_file"
    output_log=$(mktemp)
    csv_line="$file,"
    log "$transformer_name: $file"
    if [[ -f $(output-csv) ]] && grep -qP "^\Q$csv_line\E" "$(output-csv)"; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress transform)"
    mkdir -p "$(dirname "$output")"
    compile-lambda transformer "$transformer"
    if ! is-file-empty "$input"; then
        # shellcheck disable=SC2046
        measure "$timeout" $(transformer "$input" "$output") | tee "$output_log"
    fi
    if ! is-file-empty "$input" && ! is-file-empty "$output"; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        new_file=NA
    fi
    csv_line+="${new_file#./},$transformer_name,$(grep -oP "^measure_time=\K.*" < "$output_log")"
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
    rm-safe "$output_log"
    append-atomically "$(output-csv)" "$csv_line"
}

# transforms a list of files from one file format to another
transform-files(csv_file, input_extension, output_extension, transformer_name, transformer, data_fields=, data_extractor=, timeout=0, jobs=1) {
    assert-command parallel
    if [[ ! -f $(output-csv) ]]; then
        echo -n "${input_extension}_file,${output_extension}_file,${output_extension}_transformer,${output_extension}_time" > "$(output-csv)"
        if [[ -n $data_fields ]]; then
            echo ",${data_fields//-/_}" >> "$(output-csv)"
        else
            echo >> "$(output-csv)"
        fi
    fi
    # to avoid the constant overhead from parallelization due to reloading torte, run sequentially if only one job is requested
    if [[ $jobs -eq 1 ]]; then
        while IFS= read -r file; do
            transform-file "$file" "$input_extension" "$output_extension" "$transformer_name" "$transformer" "$data_fields" "$data_extractor" "$timeout"
        done < <(table-field "$csv_file" "${input_extension}_file" | grep -v NA$ | sort -V)
    else
        table-field "$csv_file" "${input_extension}_file" | grep -v NA$ | sort -V \
            | parallel -q ${jobs:+"-j$jobs"} "$SRC_DIRECTORY/main.sh" \
            transform-file "{}" "$input_extension" "$output_extension" "$transformer_name" "$transformer" "$data_fields" "$data_extractor" "$timeout"
    fi
}

# returns additional data fields for DIMACS files
dimacs-data-fields() {
    echo dimacs_variables,dimacs_literals
}

# returns a data extractor lambda for DIMACS files
dimacs-data-extractor() {
    lambda output,output_log echo '$(grep -E ^p < "$output" | cut -d" " -f3),$(grep -E "^[^pc]" < "$output" | grep -Fo " " | wc -l)'
}

# transforms files to various formats using FeatJAR
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
            --transformation "${transformer//-/}")" \
        "$data_fields" \
        "$data_extractor" \
        "$timeout" \
        "$jobs"
}

# transforms files to DIMACS using FeatJAR
transform-to-dimacs-with-featjar(input_extension, output_extension, transformer, timeout=0, jobs=1) {
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

# transforms kconfigreader model files to DIMACS using kconfigreader
transform-model-to-dimacs-with-kconfigreader(input_extension=model, output_extension=dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        transform-model-to-dimacs-with-kconfigreader \
        "$(lambda input,output 'echo /home/kconfigreader/run.sh '$(memory-limit 1)' de.fosd.typechef.kconfig.TransformIntoDIMACS "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout" \
        "$jobs"
}

# transforms SMT files to DIMACS using Z3
transform-smt-to-dimacs-with-z3(input_extension=smt, output_extension=dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        transform-smt-to-dimacs-with-z3 \
        "$(lambda input,output 'echo python3 smt2dimacs.py "$input" "$output"')" \
        "$(dimacs-data-fields)" \
        "$(dimacs-data-extractor)" \
        "$timeout" \
        "$jobs"
}

# displays community structure of a DIMACS file with SATGraf
draw-community-structure-with-satgraf(input_extension=dimacs, output_extension=jpg, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        dimacs_to_jpg_satgraf \
        "$(lambda input,output 'echo ./satgraf.sh "$input" "$output"')" \
        satgraf_modularity \
        "$(lambda output,output_log 'grep -v ^measure_ < "$output_log"')" \
        "$timeout" \
        "$jobs"
}

# computes backbone of a DIMACS file using kissat or cadiback
transform-dimacs-to-backbone-dimacs-with(transformer, input_extension=dimacs, output_extension=backbone.dimacs, timeout=0, jobs=1) {
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        "dimacs_to_backbone_dimacs_$transformer" \
        "$(lambda input,output 'echo python3 backbone_'"$transformer"'.py --input "$input" --backbone "$(dirname "$output")/$(basename "$output" .dimacs).backbone" --output "$output"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}

# computes all features mentioned in an extractor's intermediate files
# outputs a .model.features file, which has one feature per line, stripped of the CONFIG_ prefix
# unfortunately, this is not necessarily identical to the .features file created during extraction by the extractor
# the creation of such a .features file is extractor-dependent, and some extractors do not create it at all
# thus, we recreate it here from the intermediate files, which creates a more reliable and standardized list of features
compute-model-features-helper(input, output) {
    local kextractor_file
    kextractor_file="$(dirname "$input")/$(basename "$input" .model).kextractor"
    if [[ -f $kextractor_file ]]; then
        # this formula was extracted with KClause
        grep -E "^config " "$kextractor_file" | cut -d' ' -f2 | sed 's/^CONFIG_//'
    else
        # this formula was extracted with KConfigReader and already mentions all variables in the model file
        grep -E "^#item " "$input" | cut -d' ' -f2
    fi | sort | uniq > "$output"
}

# for model files, computes all features that are constrained (i.e., mentioned in the formula)
# outputs a .constrained.features file, which is a subset of the features in the .model.features file
compute-constrained-features-helper(input, output) {
    # extract features mentioned in the model file (i.e., the formula)
    if grep -q "def(" "$input"; then
        sed "s/)/)\n/g" < "$input" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g"
    elif grep -q "definedEx(" "$input"; then # todo: handle ConfigFix, more gracefully, and unify both cases?
        sed "s/)/)\n/g" < "$input" | grep "definedEx(" | sed "s/.*definedEx(\(.*\)).*/\1/g"
    fi | sort | uniq > "$output"
}

# for model files, computes all features that are unconstrained (i.e., not mentioned in the formula)
# outputs a .unconstrained.features file, which is a subset of the features in the .model.features file
compute-unconstrained-features-helper(input, output) {
    local tmp_formula tmp_model
    tmp_formula=$(mktemp)
    tmp_model=$(mktemp)
    # features mentioned in the formula
    compute-constrained-features-helper "$input" "$tmp_formula"
    # all features the extractor has found
    compute-model-features-helper "$input" "$tmp_model"
    # subtract the latter from the former
    diff "$tmp_formula" "$tmp_model" | grep '>' | cut -d' ' -f2 > "$output"
    rm-safe "$tmp_formula" "$tmp_model"
}

# extracts core or dead features from a backbone dimacs file (excludes Tseitin variables for efficiency)
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
# outputs a .backbone.features file, which is a subset of the features mentioned in the formula
# only core and dead features are included, with + and - prefixes, respectively
compute-backbone-features-helper(input, output) {
    compute-core-or-dead-features "$input" "$output" '' | awk '{print "+" $0}' > "$output"
    compute-core-or-dead-features "$input" "$output" '-' | awk '{print "-" $0}' >> "$output"
}

# computes different kinds of feature sets from a given .model file
compute-features(kind=model, output_extension=, timeout=0, jobs=1) {
    if [[ $kind == backbone ]]; then
        local input_extension=backbone.dimacs
    elif [[ $kind == model ]] || [[ $kind == constrained ]] || [[ $kind == unconstrained ]]; then
        local input_extension=model
    else
        error "Unknown feature set kind: $kind"
    fi
    output_extension=${output_extension:-${kind}.features}
    transform-files \
        "$(input-csv)" \
        "$input_extension" \
        "$output_extension" \
        "compute-${kind}-features" \
        "$(lambda input,output 'echo '"$SRC_DIRECTORY/main.sh"' "compute-'"$kind"'-features-helper" "$input" "$output"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}

# provides a pseudo-random source based on a seed, which is much less predictable than passing --random-source=<(yes "$seed")
pseudo-random-source(seed) {
    openssl enc -aes-256-ctr -pass pass:"$seed" -nosalt -out /dev/stdout </dev/zero 2>/dev/null
}

# helper function to compute a random t-wise sample of lines from a file of a given size
compute-random-sample-helper(input, output, size=1, t_wise=1, separator=, seed=) {
    separator=${separator:-,}
    tmp_samples=()
    for ((i=0; i<t_wise; i++)); do
        tmp_sample=$(mktemp)
        tmp_samples+=("$tmp_sample")
        cmd=shuf
        if [[ -n "$seed" ]]; then
            cmd+=" --random-source=<(pseudo-random-source \"${seed}${i}\")"
        fi
        eval "$cmd" -n "$size" "$input" > "$tmp_sample"
    done
    paste -d "$separator" "${tmp_samples[@]}" > "$output"
    rm -f "${tmp_samples[@]}"
}

# compute a random sample of lines of the given line-delimited files
# has the slight technical limitation that the separator cannot be empty or whitespace
compute-random-sample(extension, size=1, t_wise=1, separator=, seed=, timeout=0, jobs=1) {
    separator=${separator:-,}
    transform-files \
        "$(input-csv)" \
        "$extension" \
        "$extension" \
        "compute-random-sample" \
        "$(lambda input,output 'echo '"$SRC_DIRECTORY/main.sh"' compute-random-sample-helper "$input" "$output" "'"$size"'" "'"$t_wise"'" "'"$separator"'h" "'"$seed"'"')" \
        "" \
        "" \
        "$timeout" \
        "$jobs"
}
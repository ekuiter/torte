#!/bin/bash

# analyzes a file
# measures the analysis time
analyze-file(file, analyzer_name, analyzer, data_fields=, data_extractor=, timeout=0, ignore_exit_code=, attempts=, attempt_grouper=) {
    attempt_grouper=${attempt_grouper:-$(lambda file echo default)}
    local input
    input="$(input-directory)/$file"
    compile-lambda analyzer "$analyzer"
    compile-lambda attempt-grouper "$attempt_grouper"
    local output_log
    output_log=$(mktemp)
    local timeout_file
    timeout_file=$(output-file "$(attempt-grouper "$file").timeout" "$stage")
    log "$analyzer_name: $file" "$(echo-progress analyze)"
    local timeouts
    timeouts="$(wc -l 2>/dev/null < "$timeout_file" || echo 0)"
    local fail_fast=
    if [[ -n $attempts ]] && [[ $timeouts -ge $attempts ]]; then
        fail_fast=y
    fi
    # shellcheck disable=SC2046
    if [[ -z $fail_fast ]]; then
        evaluate "$timeout" $(analyzer "$input") | tee "$output_log"
    fi
    if [[ -z $fail_fast ]] && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^evaluate_exit_code=\K.*" < "$output_log") -eq 0 ]]; }; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
    fi
    if grep -q "^evaluate_timeout=y" < "$output_log"; then
        echo "$file" >> "$timeout_file"
    fi
    local csv_line=""
    csv_line+="$file,$analyzer_name,$(grep -oP "^evaluate_time=\K.*" < "$output_log" || echo)"
    if [[ -n $data_extractor ]]; then
        if [[ -z $fail_fast ]] && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^evaluate_exit_code=\K.*" < "$output_log") -eq 0 ]]; }; then
            compile-lambda data-extractor "$data_extractor"
            csv_line+=",$(data-extractor "$output_log")"
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

# analyzes a list of files
analyze-files(csv_file, input_extension, analyzer_name, analyzer, data_fields=, data_extractor=, timeout=0, jobs=1, ignore_exit_code=, attempts=, attempt_grouper=) {
    echo -n "$input_extension-file,$input_extension-analyzer,$input_extension-analyzer-time" > "$(output-csv)"
    if [[ -n $data_fields ]]; then
        echo ",$data_fields" >> "$(output-csv)"
    else
        echo >> "$(output-csv)"
    fi
    table-field "$csv_file" "$input_extension-file" | grep -v NA$ | sort -V \
        | parallel -q ${jobs:+"-j$jobs"} "$SCRIPTS_DIRECTORY/$TOOL.sh" \
        analyze-file "{}" "$analyzer_name" "$analyzer" "$data_fields" "$data_extractor" "$timeout" "$ignore_exit_code" "$attempts" "$attempt_grouper"
}

solve(solver, kind=, parser=, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
    parser=${parser:-$kind}
    analyze-files \
        "$(input-csv)" \
        "$input_extension" \
        "$solver" \
        "$(lambda input 'echo '"$solver"' "$input"')" \
        "$kind" \
        "$(lambda output_log 'parse-result-'"$parser"' "$output_log"')" \
        "$timeout" \
        "$jobs" \
        y \
        "$attempts" \
        "$attempt_grouper"
}

parse-result-satisfiable(output_log) {
    if grep -q "^s SATISFIABLE\|^SATISFIABLE" "$output_log"; then
        echo true
    elif grep -q "^s UNSATISFIABLE\|^UNSATISFIABLE" "$output_log"; then
        echo false
    else
        echo NA
    fi
}

parse-result-model-count(output_log) {
    local model_count
    model_count=$(sed -z 's/\n# solutions \n/SHARPSAT/g' < "$output_log" \
        | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting... )\d+(?= models)|(?<=c model count\.{12}: )\d+|(?<=^s )\d+|(?<=^s mc )\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)
    echo "${model_count:-NA}"
}

parse-result-model-counting-competition-2022(output_log) {
    model_count_int=$(grep "c s exact .* int" < "$output_log" | cut -d' ' -f6)
    model_count_double=$(grep "c s exact double prec-sci" < "$output_log" | cut -d' ' -f6)
    model_count_log10=$(grep "c s log10-estimate" < "$output_log" | cut -d' ' -f4)
    echo "${model_count_int:-NA}"
}
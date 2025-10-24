#!/bin/bash
# solves (and applies analyses to) files

# contains additional solvers archived by SAT heritage, which are optional due to increased size
SAT_HERITAGE_URL=https://github.com/ekuiter/torte-sat-heritage
SAT_HERITAGE_SYSTEM_NAME=sat-heritage # the directory name under which SAT heritage is cloned
SAT_HERITAGE_INPUT_KEY=sat_heritage # the name of the input key to access SAT heritage solvers

# solves a file
# measures the solve time
solve-file(file, solver_name, solver, data_fields=, data_extractor=, timeout=0, ignore_exit_code=, attempts=, attempt_grouper=) {
    attempt_grouper=${attempt_grouper:-$(lambda file echo default)}
    local input
    input="$(input-directory)/$file"
    compile-lambda solver "$solver"
    compile-lambda attempt-grouper "$attempt_grouper"
    local output_log
    output_log=$(mktemp)
    local timeout_file
    timeout_file=$(output-file "$(attempt-grouper "$file").timeout")
    log "$solver_name: $file" "$(echo-progress solve)"
    local timeouts
    timeouts="$(wc -l 2>/dev/null < "$timeout_file" || echo 0)"
    local fail_fast=
    if [[ -n $attempts ]] && [[ $timeouts -ge $attempts ]]; then
        fail_fast=y
    fi
    # shellcheck disable=SC2046
    if [[ -z $fail_fast ]]; then
        measure "$timeout" $(solver "$input") | tee "$output_log"
    fi
    if [[ -z $fail_fast ]] && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^measure_exit_code=\K.*" < "$output_log") -eq 0 ]]; }; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
    fi
    if grep -q "^measure_timeout=y" < "$output_log"; then
        echo "$file" >> "$timeout_file"
    fi
    local csv_line=""
    csv_line+="$file,$solver_name,$(grep -oP "^measure_time=\K.*" < "$output_log" || echo)"
    if [[ -n $data_extractor ]]; then
        if [[ -z $fail_fast ]] && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^measure_exit_code=\K.*" < "$output_log") -eq 0 ]]; }; then
            compile-lambda data-extractor "$data_extractor"
            csv_line+=",$(data-extractor "$output_log")"
        else
            for _ in $(seq 1 $(($(echo "$data_fields" | tr -cd , | wc -c)+1))); do
                csv_line+=",NA"
            done
        fi
    fi
    rm-safe "$output_log"
    # technically, this write is unsafe when using parallel jobs.
    # however, as long as the line is not too long, the write buffer saves us.
    # see https://unix.stackexchange.com/q/42544/
    echo "$csv_line" >> "$(output-csv)"
}

# solves a list of files
solve-files(csv_file, input_extension, solver_name, solver, data_fields=, data_extractor=, timeout=0, jobs=1, ignore_exit_code=, attempts=, attempt_grouper=) {
    echo -n "${input_extension}_file,${input_extension}_solver,${input_extension}_solver_time" > "$(output-csv)"
    if [[ -n $data_fields ]]; then
        echo ",${data_fields//-/_}" >> "$(output-csv)"
    else
        echo >> "$(output-csv)"
    fi
    table-field "$csv_file" "${input_extension}_file" | grep -v NA$ | sort -V \
        | parallel -q ${jobs:+"-j$jobs"} "$SRC_DIRECTORY/main.sh" \
        solve-file "{}" "$solver_name" "$solver" "$data_fields" "$data_extractor" "$timeout" "$ignore_exit_code" "$attempts" "$attempt_grouper"
}

# runs a solver on a file
solve(solver, kind=, parser=, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
    parser=${parser:-$kind}
    solve-files \
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

# parses results of typical satisfiability solvers
parse-result-sat(output_log) {
    if grep -q "^s SATISFIABLE\|^SATISFIABLE" "$output_log"; then
        echo true
    elif grep -q "^s UNSATISFIABLE\|^UNSATISFIABLE" "$output_log"; then
        echo false
    else
        echo NA
    fi
}

# parses results of various model counters
parse-result-sharp-sat(output_log) {
    local model_count
    model_count=$(sed -z 's/\n# solutions \n/SHARPSAT/g' < "$output_log" \
        | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting... )\d+(?= models)|(?<=c model count\.{12}: )\d+|(?<=^s )\d+|(?<=^s mc )\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)
    echo "${model_count:-NA}"
}

# parses results of model counters that use the format of the model-counting competition 2022
parse-result-sharp-sat-mcc22(output_log) {
    model_count_int=$(grep "^c s exact .* int" < "$output_log" | cut -d' ' -f6)
    model_count_double=$(grep "^c s exact double prec-sci" < "$output_log" | cut -d' ' -f6)
    model_count_log10=$(grep "^c s log10-estimate" < "$output_log" | cut -d' ' -f4)
    echo "${model_count_int:-NA}"
}

# runs a Jupyter notebook and stores its converts its results into an HTML file
run-jupyter-notebook(payload_file, to=html, options=) {
    export PYDEVD_DISABLE_FILE_VALIDATION=1
    export DOCKER_SRC_DIRECTORY
    jupyter nbconvert --to "$to" ${options:+"$options"} --execute --output-dir "$(output-directory)" "$SRC_EXPERIMENT_DIRECTORY/$payload_file"
}

# computes differences for model files with clausy
run-clausy-batch-diff(input_directory=, timeout=0) {
    input_directory=${input_directory:-$(input-directory)}
    scripts/batch_diff.sh "$input_directory" "$timeout" > "$(output-csv)"
}

# denote the intent to clone SAT heritage solvers in the experiment
add-sat-heritage() {
    add-hook-step post-experiment-systems-hook sat-heritage "$(to-lambda post-experiment-systems-hook-sat-heritage)"
}

# clone additional SAT heritage solvers, so they can be used in solving stages
post-experiment-systems-hook-sat-heritage() {
    add-system --system "$SAT_HERITAGE_SYSTEM_NAME" --url "$SAT_HERITAGE_URL"
}

# expresses the intent to mount additional SAT heritage solvers in solving stages
# can be passed as --input to solve(...)
# assumes that SAT heritage was cloned before using add-sat-heritage
mount-sat-heritage(input=transform-model-to-dimacs, sat_heritage=clone-systems) {
    echo "$MAIN_INPUT_KEY=$input,$SAT_HERITAGE_INPUT_KEY=$sat_heritage"
}

# selects a solver from SAT heritage to be run inside a solving stage
# can be used inside the --solver_specs of solve(...)
solve-sat-heritage(solver) {
    echo "$DOCKER_INPUT_DIRECTORY/$SAT_HERITAGE_INPUT_KEY/$SAT_HERITAGE_SYSTEM_NAME/run.sh $solver"
}
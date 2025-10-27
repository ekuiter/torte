#!/bin/bash
# solves (and applies analyses to) files

# contains additional solvers archived by SAT heritage, which are optional due to increased size
SAT_HERITAGE_URL=https://github.com/ekuiter/torte-sat-heritage
SAT_HERITAGE_SYSTEM_NAME=sat-heritage # the directory name under which SAT heritage is cloned
SAT_HERITAGE_INPUT_KEY=sat_heritage # the name of the input key to access SAT heritage solvers

# solves a file
# measures the solve time
# optionally applies multiple solver queries
solve-file(file, input_extension, solver_name, solver, data_fields=, data_extractor=, timeout=0, ignore_exit_code=, attempts=, attempt_grouper=, query_iterator=) {
    local input output_log timeout_file csv_line timeouts fail_fast
    input="$(input-directory)/$file" # the file we are going to solve (before applying the query)
    output="$(output-directory)/$(dirname "$file")/$(basename "$file")" # the input file for the solver (after applying the query)
    state="$(output-directory)/$(dirname "$file")/$(basename "$file" ".$input_extension").iterator" # the query iterator state
    mkdir -p "$(dirname "$state")"
    output_log=$(mktemp)
    csv_line="$file,"
    log "$solver_name: $file"
    
    # skip if already solved
    if [[ -f $(output-csv) ]] && grep -qP "^\Q$csv_line\E" "$(output-csv)"; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress solve)"

    # can only solve if the input file is present
    if is-file-empty "$input"; then
        fail_fast=y
    fi

    # determine the first solver query and prepare the first file to be solved
    query_iterator=${query_iterator:-$(to-lambda query-void)}
    compile-lambda query-iterator "$query_iterator"
    next_query=$(query-iterator "$input" "$output" "$state")

    # iterate over all queries to be solved for the given file
    while [[ -n $next_query ]]; do
        # in case of a certain number of successive timeouts, skip any further attempts
        # this is useful if files are executed in order of increasingly complexity, as later files will likely not be solvable either
        # if files naturally cluster into several groups of increasing complexity (like Linux's architectures), we can optionally group them accordingly
        attempt_grouper=${attempt_grouper:-$(lambda file echo default)}
        compile-lambda attempt-grouper "$attempt_grouper"
        timeout_file=$(output-file "$(attempt-grouper "$file" "$next_query").timeout")
        timeouts="$(wc -l 2>/dev/null < "$timeout_file" || echo 0)"
        if [[ -n $attempts ]] && [[ $timeouts -ge $attempts ]]; then
            fail_fast=y
        fi

        # attempt to solve the file with the solver
        if [[ -z $fail_fast ]]; then
            compile-lambda solver "$solver"
            # shellcheck disable=SC2046
            measure "$timeout" $(solver "$output") | tee "$output_log"
        fi

        # check and log whether the solving attempt was successful
        local success
        if [[ -z $fail_fast ]] \
            && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^measure_exit_code=\K.*" < "$output_log") -eq 0 ]]; } \
            && ! grep -q "^measure_timeout=y" < "$output_log"; then
            success=y
        fi
        if [[ -n $success ]]; then
            log "" "$(echo-done)"
            rm-safe "$timeout_file"
        else
            log "" "$(echo-fail)"
        fi

        # in case of timeout, append this attempt to the timeout file, so further attempts can potentially be skipped
        if grep -q "^measure_timeout=y" < "$output_log"; then
            append-atomically "$timeout_file" "$file"
        fi
        
        # collect results into CSV line
        csv_line+="$solver_name,$next_query,$(grep -oP "^measure_time=\K.*" < "$output_log" || echo)"

        # collect additional data fields (e.g., satisfiability or model count) if requested and if solving succeeded
        if [[ -n $data_extractor ]]; then
            if [[ -n $success ]]; then
                compile-lambda data-extractor "$data_extractor"
                csv_line+=",$(data-extractor "$output_log")"
            else
                for _ in $(seq 1 $(($(echo "$data_fields" | tr -cd , | wc -c)+1))); do
                    csv_line+=",NA"
                done
            fi
        fi

        # clean up and append results to CSV file
        rm-safe "$output_log"
        append-atomically "$(output-csv)" "$csv_line"

        # advance iterator to next query
        next_query=$(query-iterator "$input" "$output" "$state")
    done

    # clean up redundant state files
    rm-safe "$output" "$state"
}

# solves a list of files
solve-files(csv_file, input_extension, solver_name, solver, data_fields=, data_extractor=, timeout=0, jobs=1, ignore_exit_code=, attempts=, attempt_grouper=, query_iterator=) {
    if [[ -n $attempts ]] && [[ $jobs -gt 1 ]]; then
        error "Cannot use parallel jobs when detecting consecutive timeouts, as this requires sequential timeout tracking."
    fi
    if [[ ! -f $(output-csv) ]]; then
        echo -n "${input_extension}_file,${input_extension}_solver,${input_extension}_query,${input_extension}_solver_time" > "$(output-csv)"
        if [[ -n $data_fields ]]; then
            echo ",${data_fields//-/_}" >> "$(output-csv)"
        else
            echo >> "$(output-csv)"
        fi
    fi
    # to avoid the constant overhead from parallelization due to reloading torte, run sequentially if only one job is requested
    if [[ $jobs -eq 1 ]]; then
        while IFS= read -r file; do
            solve-file "$file" "$input_extension" "$solver_name" "$solver" "$data_fields" "$data_extractor" "$timeout" "$ignore_exit_code" "$attempts" "$attempt_grouper" "$query_iterator"
        done < <(table-field "$csv_file" "${input_extension}_file" | grep -v NA$ | sort -V)
    else  
        table-field "$csv_file" "${input_extension}_file" | grep -v NA$ | sort -V \
            | parallel -q ${jobs:+"-j$jobs"} "$SRC_DIRECTORY/main.sh" \
            solve-file "{}" "$input_extension" "$solver_name" "$solver" "$data_fields" "$data_extractor" "$timeout" "$ignore_exit_code" "$attempts" "$attempt_grouper" "$query_iterator"
    fi
}

# runs a solver on a file
solve(solver, kind=, parser=, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, query_iterator=) {
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
        "$attempt_grouper" \
        "$query_iterator"
}

# performs a single solver call on the given input file
# corresponds to void analysis for SAT solvers
# and feature-model cardinality for #SAT solvers
query-void(input, output, state) {
    if [[ ! -f "$state" ]]; then
        cp "$input" "$output"
        echo void
    fi
    touch "$state"
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

# parses results of various #SAT solvers
parse-result-sharp-sat(output_log) {
    local model_count
    model_count=$(sed -z 's/\n# solutions \n/SHARPSAT/g' < "$output_log" \
        | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting... )\d+(?= models)|(?<=c model count\.{12}: )\d+|(?<=^s )\d+|(?<=^s mc )\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)
    echo "${model_count:-NA}"
}

# parses results of #SAT solvers that use the format of the model-counting competition 2022
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
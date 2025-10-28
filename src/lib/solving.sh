#!/bin/bash
# solves (and applies analyses to) files

# contains additional solvers archived by SAT heritage, which are optional due to increased size
SAT_HERITAGE_URL=https://github.com/ekuiter/torte-sat-heritage
SAT_HERITAGE_SYSTEM_NAME=sat-heritage # the directory name under which SAT heritage is cloned
SAT_HERITAGE_INPUT_KEY=sat_heritage # the name of the input key to access SAT heritage solvers
QUERY_SAMPLE_INPUT_KEY=query_sample # the name of the input key to access which feature sample to query

# solves a file
# measures the solve time
# optionally applies multiple solver queries
solve-file(file, input_extension, solver_name, solver, data_fields=, data_extractor=, timeout=0, ignore_exit_code=, attempts=, attempt_grouper=, query_iterator=) {
    local input output_log timeout_file csv_line timeouts fail_fast
    input="$(input-directory)/$file" # the file we are going to solve (before applying the query)
    output="$(output-directory)/$(dirname "$file")/$(basename "$file")" # the input file for the solver (after applying the query)
    state="$(output-directory)/$(dirname "$file")/$(basename "$file" ".$input_extension").iterator" # the query iterator state
    query_iterator=${query_iterator:-$(to-lambda query-void)} # by default, just perform a single solver call on the given input file
    mkdir -p "$(dirname "$state")"
    output_log=$(mktemp)
    
    # skip if already solved
    if [[ -f $(output-csv) ]] && grep -qP "^\Q$file,\E" "$(output-csv)"; then
        log "$solver_name: $file" "$(echo-skip)"
        return
    fi
    source-lambda "$solver"
    source-lambda "$data_extractor"
    source-lambda "$attempt_grouper"
    source-lambda "$query_iterator"

    # can only solve if the input file is present
    if is-file-empty "$input"; then
        fail_fast=y
    fi

    # determine the first solver query and prepare the first file to be solved
    next_query=$("$query_iterator" "$file" "$input" "$input_extension" "$output" "$state")

    # iterate over all queries to be solved for the given file
    while [[ -n $next_query ]]; do
        log "$solver_name: $file [$next_query]"
        log "" "$(echo-progress solve)"
        csv_line="$file,"

        # in case of a certain number of successive timeouts, skip any further attempts
        # this is useful if files are executed in order of increasingly complexity, as later files will likely not be solvable either
        # if files naturally cluster into several groups of increasing complexity (like Linux's architectures), we can optionally group them accordingly
        if [[ -n $attempt_grouper ]]; then
            timeout_file=$(output-file "$("$attempt_grouper" "$file" "$next_query").timeout")
        else
            timeout_file=$(output-file "default.timeout")
        fi
        timeouts="$(wc -l 2>/dev/null < "$timeout_file" || echo 0)"
        if [[ -n $attempts ]] && [[ $timeouts -ge $attempts ]]; then
            fail_fast=y
        fi

        # attempt to solve the file with the solver
        if [[ -z $fail_fast ]]; then
            # shellcheck disable=SC2046
            measure "$timeout" $("$solver" "$output") | tee "$output_log"
        fi

        # check whether the solving attempt was successful
        local success
        if [[ -z $fail_fast ]] \
            && { [[ -n $ignore_exit_code ]] || [[ $(grep -oP "^measure_exit_code=\K.*" < "$output_log") -eq 0 ]]; } \
            && ! grep -q "^measure_timeout=y" < "$output_log"; then
            success=y
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
                csv_line+=",$("$data_extractor" "$output_log")"
            else
                for _ in $(seq 1 $(($(echo "$data_fields" | tr -cd , | wc -c)+1))); do
                    csv_line+=",NA"
                done
            fi
        fi

        # clean up and append results to CSV file
        rm-safe "$output_log"
        append-atomically "$(output-csv)" "$csv_line"

        # report success or failure
        if [[ -n $success ]]; then
            log "" "$(echo-done)"
            rm-safe "$timeout_file"
        else
            log "" "$(echo-fail)"
        fi

        # advance iterator to next query
        next_query=$("$query_iterator" "$file" "$input" "$input_extension" "$output" "$state")
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
# this corresponds to void analysis for SAT solvers, and feature-model cardinality for #SAT solvers
query-void(file, input, input_extension, output, state) {
    if [[ ! -f "$state" ]]; then
        touch "$state"
        cp "$input" "$output"
        echo void
    fi
}

# performs a complex solver query, where arbitrary unit-clause assumptions are allowed
# polarities is a comma-separated string of '+' and '-' characters indicating the state of the corresponding feature
query-complex(kind, polarities, features_extension, file, input, input_extension, output, state) {
    local feature
    if [[ ! -f "$state" ]]; then
        cp "$DOCKER_INPUT_DIRECTORY/$QUERY_SAMPLE_INPUT_KEY/$(dirname "$file")/$(basename "$file" ".$input_extension").$features_extension" "$state"
    fi
    features=$(head -n1 "$state")
    if [[ -z $features ]]; then
        return
    fi
    sed -i '1d' "$state"
    cp "$input" "$output"
    to-array features
    to-array polarities
    echo -n "$kind"
    for i in "${!features[@]}"; do
        feature="${features[$i]}"
        polarity="${polarities[$i]}"
        echo -n " $polarity$feature"
        dimacs-assume "$output" "$feature" "${polarity/+/}"
    done
    echo
}

# queries the solver regarding whether the given partial configuration is valid
# this is meant to be used together with compute-random-sample(...) and --t-wise > 1
query-partial(polarities, features_extension, file, input, input_extension, output, state) {
    query-complex partial "$polarities" "$features_extension" "$file" "$input" "$input_extension" "$output" "$state"
}

# queries the solver regarding whether the given features are core
query-core(features_extension, file, input, input_extension, output, state) {
    query-complex core - "$features_extension" "$file" "$input" "$input_extension" "$output" "$state"
}

# queries the solver regarding whether the given features are dead
query-dead(features_extension, file, input, input_extension, output, state) {
    query-complex dead + "$features_extension" "$file" "$input" "$input_extension" "$output" "$state"
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

# expresses the intent to mount the default input in solving stages
# can be passed as --input to solve(...)
mount-input(input=transform-model-to-dimacs) {
    echo "$MAIN_INPUT_KEY=$input"
}

# expresses the intent to mount a query sample in solving stages
# can be passed as --input to solve(...)
mount-query-sample(input) {
    echo "$QUERY_SAMPLE_INPUT_KEY=$input"
}

# denote the intent to clone SAT heritage solvers in the experiment
add-sat-heritage() {
    add-hook-step post-experiment-systems-hook post-experiment-systems-hook-sat-heritage
}

# clone additional SAT heritage solvers, so they can be used in solving stages
post-experiment-systems-hook-sat-heritage() {
    add-system --system "$SAT_HERITAGE_SYSTEM_NAME" --url "$SAT_HERITAGE_URL"
}

# expresses the intent to mount SAT heritage solvers in solving stages
# can be passed as --input to solve(...)
# assumes that SAT heritage was cloned before using add-sat-heritage
mount-sat-heritage(input=clone-systems) {
    echo "$SAT_HERITAGE_INPUT_KEY=$input"
}

# selects a solver from SAT heritage to be run inside a solving stage
# can be used inside the --solver_specs of solve(...)
solve-sat-heritage(solver) {
    echo "$DOCKER_INPUT_DIRECTORY/$SAT_HERITAGE_INPUT_KEY/$SAT_HERITAGE_SYSTEM_NAME/run.sh $solver"
}
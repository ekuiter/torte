#!/bin/bash
# runs experiments

ORIGINAL_EXPERIMENT_FILE= # original experiment file path, required for finding payload files

# where to store the preprocessed experiment file
SRC_EXPERIMENT_DIRECTORY=$SRC_DIRECTORY/experiment
SRC_EXPERIMENT_FILE=$SRC_EXPERIMENT_DIRECTORY/experiment.sh

# returns the path to a given experiment file
experiment-file(experiment_file=default) {
    if [[ -f $experiment_file ]]; then
        echo "$experiment_file"
    elif [[ -f $TOOL_DIRECTORY/experiments/$experiment_file/experiment.sh ]]; then
        echo "$TOOL_DIRECTORY/experiments/$experiment_file/experiment.sh"
    fi
}

# returns the path to a given payload file
payload-file(payload_file) {
    payload_file=$SRC_EXPERIMENT_DIRECTORY/$payload_file
    [[ -f $payload_file ]] && echo "$payload_file"
}

# adds a new payload file
# these are files of interest that reside besides the experiment file, such as Jupyter notebooks
add-payload-file(payload_file) {
    if is-host; then
        local original_payload_file src_payload_file
        original_payload_file=$(dirname "$ORIGINAL_EXPERIMENT_FILE")/$payload_file
        src_payload_file=$SRC_EXPERIMENT_DIRECTORY/$payload_file
        if [[ $payload_file == "$(basename "$ORIGINAL_EXPERIMENT_FILE")" ]]; then
            error-help "The payload file $payload_file cannot be the experiment file."
        elif [[ ! -f $original_payload_file ]] && [[ -n $TORTE_EXPERIMENT ]] && [[ -f $(dirname "$(experiment-file "$TORTE_EXPERIMENT")")/$payload_file ]]; then
            # this addresses the corner case where the experiment file has been obtained with the one-liner from the README file (which sets TORTE_EXPERIMENT)
            # in that case, we obtain the payload from this project's repository
            local repository_payload_file
            repository_payload_file=$(dirname "$(experiment-file "$TORTE_EXPERIMENT")")/$payload_file
            cp "$repository_payload_file" "$original_payload_file"
        elif [[ ! -f $original_payload_file ]]; then
            error-help "The requested payload file $payload_file does not exist and cannot be added."
        fi
        mkdir -p "$SRC_EXPERIMENT_DIRECTORY"
        cp "$original_payload_file" "$src_payload_file"
    fi
}

# downloads a new payload file from a URL and adds it
download-payload-file(payload_file, url) {
    if is-host; then
        local original_payload_file
        original_payload_file=$(dirname "$ORIGINAL_EXPERIMENT_FILE")/$payload_file
        if [[ ! -f $original_payload_file ]]; then
            assert-command curl
            curl -fsSL "$url" -o "$original_payload_file"
        fi
        add-payload-file "$payload_file"
    fi
}

# adds a restrictions payload file, compiles it, and loads it
# this creates the global scope function should-skip, which can be used to skip certain combinations of stages, systems, or analyses
add-restrictions-payload-file(payload_file) {
    add-payload-file "$payload_file"
    # shellcheck disable=SC1090
    source <(compile-script <(compile-restrictions "$(payload-file "$payload_file")"))
}

# precompiles restrictions from a CSV file into a single efficient Bash function, which is only loaded once (at experiment load time)
# each line in the CSV file should contain one restriction, for which every non-empty field must match for the restriction to apply
# if any restriction applies, the corresponding action will not be performed and skipped instead
# thus, this mechanism is useful to for bit specific combinations of stages, systems, or analyses
# (e.g., to skip distributive CNF transformation for systems where it is known not to scale)
# this is also useful to temporarily disable certain actions without having to modify the experiment file itself
# the special comment field can be used to add human-readable comments to each restriction line (e.g., to add a rationale)
# fields are matched using Bash's ==, so glob patterns are supported (e.g., to match only a major revision of a system)
# no subshells are spawned by the generated function, to ensure maximum performance
# this mechanism resembles query-by-example (QBE) in that we specify specific interactions to filter out
# it also resembles aspect-oriented programming (AOP) in that we define "pointcuts" (restrictions) and "weave" them in at compile time
# the excluded actions will not be logged in CSV files, as they are considered excluded from the experiment by design
# this is an example restrictions file (use with "add-restrictions-payload-file restrictions.csv"):
# pass,stage,function,argument,system,revision,file,comment
# ,,add-system,,sat-heritage,,,temporarily skip cloning the large Linux Git repository
# ,extract-kconfig-models-with-kconfigreader,,,,,,fully skip KConfigReader extraction
# ,transform-to-xml-with-featureide,,,,,extract-kconfig-models-with-configfix/*,skip XML transformation for formulas extracted by ConfigFix
# ,transform-to-dimacs-with-featureide,,,,,*/linux/*v6.*,skip expensive distributive transformation for recent Linux versions
# second,,extract-kconfig-model,,,,,fully skip extraction in the second pass
# ,solve-emse-2023-d4,,,,,transform-to-dimacs-with-kconfigreader/*,skip model counting for Plaisted-Greenbaum transformation
# ,,solve-file,"core -"*,,,,skip all core feature queries (this requires quotes because of the dash)
# ,,solve-file,*FEATURE_NAME*,,,,skip all queries related to a specific feature
compile-restrictions(restrictions_file) {
    if [[ ! -f $restrictions_file ]]; then
        error "Cannot compile restrictions: file $restrictions_file does not exist."
    fi
    echo "should-skip(function=, argument=, system=, revision=, file=) {"
    {
        read -r header
        while IFS= read -r row || [[ -n $row ]]; do
            echo -n "    if true"
            for col in $(echo "$header" | tr , "\n"); do
                local value
                value=$(echo "$row" | cut -d, -f"$(table-field-index "$restrictions_file" "$col")")
                if [[ $col == comment ]]; then
                    continue
                fi
                if [[ $col == pass ]]; then
                    col=PASS
                fi
                if [[ $col == stage ]]; then
                    col=INSIDE_STAGE
                fi
                if [[ -n $value ]]; then
                    echo -n " && [[ \$$col == $value ]]"
                fi
            done
            echo "; then return 0; fi"
        done
    } < "$restrictions_file"
    echo "    return 1"
    echo "}"
    echo
}

# prepares an experiment by loading its file
# this has no effect besides defining (global) variables and functions
load-experiment(experiment_file=default) {
    if is-host; then
        experiment_file=$(experiment-file "$experiment_file")
        if [[ -z $experiment_file ]]; then
            error-help "Please provide an experiment in $experiment_file."
        fi
        ORIGINAL_EXPERIMENT_FILE=$experiment_file
        if [[ ! $experiment_file -ef $SRC_EXPERIMENT_FILE ]]; then
            rm-safe "$SRC_EXPERIMENT_DIRECTORY"
            mkdir -p "$SRC_EXPERIMENT_DIRECTORY"
            cp "$experiment_file" "$SRC_EXPERIMENT_FILE"
        fi
    fi
    source-script "$SRC_EXPERIMENT_FILE"
    
    # override experiment-systems with experiment-test-systems if TEST is enabled
    if [[ -n $TEST ]]; then
        if declare -f experiment-test-systems > /dev/null; then
            experiment-systems() {
                experiment-test-systems
            }
        else
            echo "Test mode is enabled, but no test systems are defined in $experiment_file. Skipping tests."
            exit
        fi
    fi
}

# lists all stages with their numbers in a user-friendly table format
list-stages() {
    local stages
    readarray -t numbered_stages < <(list-numbered-stages)
    if [[ ${#numbered_stages[@]} -eq 0 ]]; then
        return
    fi
    printf "┌────┬─────────────────────────────┬────────────┬────────┬──────┐\n"
    printf "│ %2s │ %-27s │ %-10s │ %6s │ %4s │\n" "#" "Stage" "Status" "Size" "#Row"
    printf "├────┼─────────────────────────────┼────────────┼────────┼──────┤\n"
    local total_complete=0 total_csv_rows=0
    for numbered_stage in "${numbered_stages[@]}"; do
        if [[ -n "$numbered_stage" ]]; then
            local stage_number stage_name status size csv_entries
            stage_number=$(get-stage-number "$numbered_stage")
            stage_name=$(get-stage-name "$numbered_stage")
            if [[ -n $stage_name ]]; then
                if stage-moved "$stage_name"; then
                    local moved_to
                    moved_to=$(stage-moved-to "$stage_name")
                    status="moved: #$(lookup-stage-number "$moved_to")"
                    total_complete=$((total_complete + 1))
                elif stage-done "$stage_name"; then
                    status="$(echo-green "done      ")"
                    total_complete=$((total_complete + 1))
                else
                    status="$(echo-yellow incomplete)"
                fi
                if [[ -d "$numbered_stage" ]] && ! stage-moved "$stage_name"; then
                    size=$(du -sh "$numbered_stage" 2>/dev/null | cut -f1 || echo "")
                else
                    size=""
                fi
                local csv_file="$numbered_stage/$OUTPUT_FILE_PREFIX.csv"
                if [[ -f "$csv_file" ]]; then
                    csv_entries=$(( $(wc -l < "$csv_file" 2>/dev/null || echo "0") - 1 ))
                    [[ $csv_entries -lt 0 ]] && csv_entries=0
                    total_csv_rows=$((total_csv_rows + csv_entries))
                else
                    csv_entries=""
                fi
                if [[ ${#stage_name} -gt 27 ]]; then
                    stage_name="${stage_name:0:24}..."
                fi
                printf "│ %2s │ %-27s │ %-10s │ %6s │ %4s │\n" \
                    "$stage_number" "$stage_name" "$status" "$size" "$csv_entries"
            fi
        fi
    done
    local total_size=""
    if [[ -d "$(stages-directory)" ]]; then
        total_size=$(du -sh "$(stages-directory)" 2>/dev/null | cut -f1 || echo "")
    fi
    printf "├────┼─────────────────────────────┼────────────┼────────┼──────┤\n"
    printf "│ %2s │ %-27s │ %-10s │ %6s │ %4s │\n" \
        "" "total" "${total_complete} done" "$total_size" "$total_csv_rows"
    printf "└────┴─────────────────────────────┴────────────┴────────┴──────┘\n"
}

# removes all stages of the experiment (optionally, only the ones after the one with the specified number)
# does not touch Docker images
command-clean(stage_number=) {
    if [[ -z "$stage_number" ]]; then
        rm-safe "$(stages-directory)"
    else
        local stages
        readarray -t numbered_stages < <(list-numbered-stages)
        for numbered_stage in "${numbered_stages[@]}"; do
            if [[ -n "$numbered_stage" ]]; then
                local current_number
                current_number=$(get-stage-number "$numbered_stage")
                if [[ "$current_number" -ge "$stage_number" ]]; then
                    rm-safe "$numbered_stage"
                fi
            fi
        done
    fi
}

# runs the experiment
command-run() {
    if is-multi-pass && [[ -z $PASS ]]; then
        # if we are just starting out with a multi-pass experiment, run all its passes recursively
        for pass in "${PASSES[@]}"; do
            log "$pass" "$(echo-progress run)"
            PASS="$pass" TORTE_BANNER_PRINTED=y "$TOOL_SCRIPT" "$SRC_EXPERIMENT_FILE"
            FORCE_NEW_LOG=y
            log "" "$(echo-done)"
        done
    else
        # run a single-pass experiment, or a given pass of a multi-pass experiment
        clear-lambdas
        list-stages
        mkdir -p "$(stages-directory)"
        clean "$EXPERIMENT_STAGE"
        mkdir -p "$(stage-directory "$EXPERIMENT_STAGE")"
        cp -R "$SRC_EXPERIMENT_DIRECTORY/" "$(stage-directory "$EXPERIMENT_STAGE")"
        touch "$(stage-done-file "$EXPERIMENT_STAGE")"
        define-stages
        if grep -q '^\s*debug\s*$' "$SRC_EXPERIMENT_FILE" \
            || grep -q "^\s*experiment-stages\s*(\s*__NO_SILENT__" "$SRC_EXPERIMENT_FILE"; then
            experiment-stages
        else
            experiment-stages \
                > >(write-log "$(stage-log "$EXPERIMENT_STAGE")") \
                2> >(write-all "$(stage-err "$EXPERIMENT_STAGE")" >&2)
        fi
    fi
}

# stops the experiment
# this assumes that only one instance of the tool is running at a time, as it will stop all container instances
command-stop() {
    readarray -t containers < <(docker ps | tail -n+2 | awk '$2 ~ /^'"$TOOL"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}

# runs the experiment on a remote server
# removes previous experiment results and reinstalls evaluation scripts
# shellcheck disable=SC2029
command-run-remote(host, file=experiment.tar.gz, directory=., sudo=) {
    assert-command ssh scp
    if [[ $sudo == y ]]; then
        sudo=sudo
    fi
    scp -r "$file" "$host:$directory"
    local cmd="(cd $directory;"
    cmd+="  tar xzvf $(basename "$file"); "
    cmd+="  rm $(basename "$file"); "
    cmd+="  screen -dmSL $TOOL $sudo bash experiment/experiment.sh; "
    cmd+=");"
    ssh "$host" "$cmd"
    echo "$TOOL is now running on $host, opening an SSH session."
    echo "To view its output, run $TOOL (Ctrl+a d to detach)."
    echo "To stop it, run $TOOL-stop."
    cmd=""
    cmd+="$TOOL() { screen -x $TOOL; };"
    cmd+="$TOOL-stop() { screen -X -S $TOOL kill; bash $directory/experiment/experiment.sh stop; };"
    cmd+="export -f $TOOL $TOOL-stop;"
    cmd+="/bin/bash"
    ssh -t "$host" "$cmd"
}

# downloads results from the remote server
command-copy-remote(host, directory=.) {
    assert-command rsync
    rsync -av "$host:$directory/$(basename "$(stages-directory)")/" "$(stages-directory)-$host-$(date "+%Y-%m-%d")"
}

# installs a Docker image on a remote server
# shellcheck disable=SC2029
command-install-remote(host, image, directory=.) {
    ssh "$host" docker image rm "${TOOL}_$image" 2>/dev/null || true
    docker save "${TOOL}_$image" | gzip -c | ssh "$host" "cat > $directory/$image.tar.gz"
    ssh "$host" docker load -i "$directory/$image.tar.gz"
}

# tests all experiments that can be tested
# to make sure each experiment is run in a new context, we explicitly run torte in a subprocess
command-test() {
    local testable_experiments=()
    # find all experiments that define experiment-test-systems
    for experiment_dir in "$TOOL_DIRECTORY"/experiments/*/; do
        local experiment_name
        experiment_name=$(basename "$experiment_dir")
        local experiment_file
        experiment_file=$(experiment-file "$experiment_name")
        if [[ -f "$experiment_file" ]] \
            && grep -q "^\s*experiment-test-systems\s*(" "$experiment_file" \
            && ([[ -z "$CI" ]] || ! grep -q "^\s*experiment-test-systems\s*(\s*__NO_CI__" "$experiment_file"); then
            testable_experiments+=("$experiment_name")
        fi
    done
    if [[ ${#testable_experiments[@]} -eq 0 ]]; then
        error "No testable experiments found (experiments must define experiment-test-systems)"
    fi
    # run each testable experiment with TEST=y
    for experiment in "${testable_experiments[@]}"; do
        log "$experiment" "$(echo-progress test)"
        # run the experiment with TEST=y in experiment-specific output directory
        STAGES_DIRECTORY="$STAGES_DIRECTORY/$experiment" TEST=y TORTE_BANNER_PRINTED=y "$TOOL_SCRIPT" "$experiment"
        FORCE_NEW_LOG=y
        log "" "$(echo-done)"
    done
    if [[ -n "$PROFILE" ]]; then
        save-speedscope
    fi
}
#!/bin/bash
# deals with paths of stages, input, and output files

DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
DOCKER_SRC_DIRECTORY=/home/${TOOL}_src # source directory inside Docker containers
MAIN_INPUT_KEY=main # the name of the canonical input key
OUTPUT_FILE_PREFIX=output # prefix for output files
STAGE_DONE_FILE=".stage_done" # file indicating stage completion
STAGE_MOVED_FILE=".stage_moved" # file indicating stage has been moved

stages-directory() {
    if [[ -z $PASS ]]; then
        echo "$STAGES_DIRECTORY"
    else
        echo "$STAGES_DIRECTORY/$PASS"
    fi
}

# extracts the stage number from a numbered stage name
get-stage-number(numbered_stage) {
    basename "$numbered_stage" | sed 's/_.*$//'
}

# extracts the base stage name from a numbered stage name
get-stage-name(numbered_stage) {
    basename "$numbered_stage" | sed 's/^[0-9]\+_//' | sed 's/_/-/g'
}

# lists all numbered stages in order
list-numbered-stages() {
    assert-host
    if [[ -d "$(stages-directory)" ]]; then
        local stages=()
        for dir in "$(stages-directory)"/[0-9]*_*; do
            if [[ -d "$dir" ]]; then
                stages+=("$dir")
            fi
        done
        printf '%s\n' "${stages[@]}" | while IFS= read -r current_stage; do
            if [[ -n "$current_stage" ]]; then
                stage_num=$(get-stage-number "$current_stage")
                printf '%03d %s\n' "$stage_num" "$current_stage"
            fi
        done | sort -n | cut -d' ' -f2-
    fi
}

# returns the next available stage number by finding the highest existing number
get-next-stage-number() {
    assert-host
    local last_numbered_stage
    last_numbered_stage=$(list-numbered-stages | tail -n 1)
    if [[ -z "$last_numbered_stage" ]]; then
        echo "1"
    else
        local last_number
        last_number=$(get-stage-number "$last_numbered_stage")
        echo "$((last_number + 1))"
    fi
}

# finds existing numbered directory for a stage, returns empty if not found
lookup-stage-directory(stage) {
    assert-host
    if [[ -d "$(stages-directory)" ]]; then
        for dir in "$(stages-directory)"/[0-9]*_"${stage//-/_}"; do
            if [[ -d "$dir" ]] && [[ "$(get-stage-name "$dir")" == "$stage" ]]; then
                echo "$dir"
                return
            fi
        done
    fi
}

# gets the stage number for a given stage name, returns empty if not found
lookup-stage-number(stage) {
    assert-host
    local existing_stage
    existing_stage=$(lookup-stage-directory "$stage")
    if [[ -n "$existing_stage" ]]; then
        get-stage-number "$existing_stage"
    fi
}

# on the host, returns the directory for where to store the output or find the input of a given stage
# automatically assigns numbers to new stages: 1_stage, 2_stage, etc.
stage-directory(stage) {
    assert-host
    if [[ "$stage" == "$EXPERIMENT_STAGE" ]]; then
        echo "$(stages-directory)/0_$EXPERIMENT_STAGE"
        return
    fi
    local existing_dir
    existing_dir=$(lookup-stage-directory "$stage")
    if [[ -n "$existing_dir" ]]; then
        echo "$existing_dir"
    else
        local stage_number
        stage_number=$(get-next-stage-number)
        echo "$(stages-directory)/${stage_number}_${stage//-/_}"
    fi
}

# follows stage moved files recursively and returns the final directory
follow-stage-directory(stage) {
    assert-host
    local current_stage="$stage"
    local path_components=()
    # follow the chain of moves, collecting path components
    while stage-moved "$current_stage"; do
        path_components+=("$current_stage")
        current_stage=$(stage-moved-to "$current_stage")
    done
    # start with the final destination directory
    local final_dir
    final_dir=$(stage-directory "$current_stage")
    # append each moved stage as a subdirectory
    for ((i=${#path_components[@]}-1; i>=0; i--)); do
        final_dir="$final_dir/${path_components[i]}"
    done
    
    echo "$final_dir"
}

# in a Docker container, returns the input directory for the given key
input-directory(key=) {
    key=${key:-$MAIN_INPUT_KEY}
    assert-container
    # for the very first stage, the input and output directory are the same
    if [[ $INSIDE_STAGE == "$ROOT_STAGE" ]]; then
        echo "$DOCKER_OUTPUT_DIRECTORY"
        else
        echo "$DOCKER_INPUT_DIRECTORY/$key"
    fi
}

# in a Docker container, returns the directory for the current stage's output
output-directory() {
    assert-container
    echo "$DOCKER_OUTPUT_DIRECTORY"
}

# returns the path to a file at a given composite path, which is created if necessary
compose-path(base_directory, components...) {
    local new_components=()
    for component in "${components[@]}"; do
        if [ -z "$component" ]; then
            continue
        fi
        new_components+=("$component")
    done
    local path
    path=$base_directory/$(printf '%s\n' "${new_components[@]}" | paste -s -d "$PATH_SEPARATOR" -)
    mkdir -p "$(dirname "$path")"
    echo "$path"
}

# miscellaneous helpers for creating paths and file names
stage-path(stage, components...) { compose-path "$(stage-directory "$stage")" "${components[@]}"; }
input-path(key=, components...) { compose-path "$(input-directory "$key")" "${components[@]}"; }
output-path(components...) { compose-path "$(output-directory)" "${components[@]}"; }
stage-file(extension, stage) { stage-path "$stage" "$OUTPUT_FILE_PREFIX.$extension"; }
input-file(extension, key=) { input-path "$key" "$OUTPUT_FILE_PREFIX.$extension"; }
output-file(extension) { output-path "$OUTPUT_FILE_PREFIX.$extension"; }
stage-done-file(stage) { stage-path "$stage" "$STAGE_DONE_FILE"; }
stage-moved-file(stage) { stage-path "$stage" "$STAGE_MOVED_FILE"; }

# standard files for experimental results, human-readable output, and errors
stage-csv(stage) { stage-file csv "$stage"; }
stage-log(stage) { stage-file log "$stage"; }
stage-err(stage) { stage-file err "$stage"; }
stage-prf(stage) { stage-file prf "$stage"; }
input-csv(key=) { input-file csv "$key"; }
input-log(key=) { input-file log "$key"; }
input-err(key=) { input-file err "$key"; }
output-csv() { output-file csv; }
output-log() { output-file log; }
output-err() { output-file err; }
output-prf() { output-file prf; }

# returns whether the given experiment stage is done
stage-done(stage) {
    assert-host
    [[ -f $(stage-done-file "$stage") ]] || stage-moved "$stage"
}

# returns whether the given stage has been moved to an aggregate stage
stage-moved(stage) {
    assert-host
    [[ -f "$(stage-moved-file "$stage")" ]]
}

# returns the name of the aggregate stage that this stage was moved to
stage-moved-to(stage) {
    assert-host
    if stage-moved "$stage"; then
        cat "$(stage-moved-file "$stage")"
    fi
}

# asserts that the given experiment stage is done
assert-stage-done(stage) {
    assert-host
    if ! stage-done "$stage"; then
        error "Stage $stage not done yet, please run stage $stage."
    fi
}
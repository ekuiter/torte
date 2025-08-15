#!/bin/bash
# deals with paths of stages, input, and output files

DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
DOCKER_SRC_DIRECTORY=/home/${TOOL}_src # source directory inside Docker containers
MAIN_INPUT_KEY=main # the name of the canonical input key
OUTPUT_FILE_PREFIX=output # prefix for output files
STAGE_DONE_FILE=".stage_done" # file indicating stage completion
STAGE_MOVED_FILE=".stage_moved" # file indicating stage has been moved

# extracts the stage number from a numbered stage name
get-stage-number(numbered_stage) {
    basename "$numbered_stage" | sed 's/_.*$//'
}

# extracts the base stage name from a numbered stage name
get-stage-name(numbered_stage) {
    basename "$numbered_stage" | sed 's/^[0-9]*_//'
}

# lists all numbered stages in order
list-numbered-stages() {
    assert-host
    if [[ -d "$STAGE_DIRECTORY" ]]; then
        local stages=()
        for dir in "$STAGE_DIRECTORY"/[0-9]*_*; do
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
    if [[ -d "$STAGE_DIRECTORY" ]]; then
        for dir in "$STAGE_DIRECTORY"/[0-9]*_"$stage"; do
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
    if [[ "$stage" == "$TOOL" ]]; then
        echo "$STAGE_DIRECTORY/0_$TOOL"
        return
    fi
    local existing_dir
    existing_dir=$(lookup-stage-directory "$stage")
    if [[ -n "$existing_dir" ]]; then
        echo "$existing_dir"
    else
        local stage_number
        stage_number=$(get-next-stage-number)
        echo "$STAGE_DIRECTORY/${stage_number}_$stage"
    fi
}

# in a Docker container, returns the input directory for the given key
input-directory(key=) {
    key=${key:-$MAIN_INPUT_KEY}
    assert-container
    echo "$DOCKER_INPUT_DIRECTORY/$key"
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
input-csv(key=) { input-file csv "$key"; }
input-log(key=) { input-file log "$key"; }
input-err(key=) { input-file err "$key"; }
output-csv() { output-file csv; }
output-log() { output-file log; }
output-err() { output-file err; }

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
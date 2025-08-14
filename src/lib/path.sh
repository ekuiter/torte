#!/bin/bash
# deals with paths of stages, input, and output files

DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
DOCKER_SRC_DIRECTORY=/home/${TOOL}_src # source directory inside Docker containers
MAIN_INPUT_KEY=main # the name of the canonical input key
OUTPUT_FILE_PREFIX=output # prefix for output files

# on the host, returns the directory for where to store the output or find the input of a given stage
stage-directory(stage) {
    assert-host
    echo "$STAGE_DIRECTORY/$stage"
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
stage-done-file(stage) { stage-path "$stage" ".done"; }

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
# todo: this does not account for an interrupted stage (maybe create a marker file at the end of each stage like .done?)
stage-done(stage) {
    assert-host
    [[ -f $(stage-done-file "$stage") ]]
}

# asserts that the given experiment stage is done
assert-stage-done(stage) {
    assert-host
    if ! stage-done "$stage"; then
        error "Stage $stage not done yet, please run stage $stage."
    fi
}
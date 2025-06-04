#!/bin/bash
# deals with input/output paths

# returns the root input directory
input-directory() {
    if is-host; then
        echo "$INPUT_DIRECTORY"
    else
        echo "$DOCKER_INPUT_DIRECTORY"
    fi
}

# returns the directory for all outputs for a given stage
output-directory(stage=) {
    if is-host; then
        require-value stage
        echo "$OUTPUT_DIRECTORY/$stage"
    else
        echo "$DOCKER_OUTPUT_DIRECTORY"
    fi
}

# returns a file with a given extension for the input of the current stage
input-file(extension) {
    echo "$(input-directory)/$DOCKER_OUTPUT_FILE_PREFIX.$extension"
}

# returns a file at a given (created if necessary) path for the output of a given stage
output-path(components...) {
    local new_components=()
    for component in "${components[@]}"; do
        if [ -z "$component" ]; then
            continue
        fi
        new_components+=("$component")
    done
    local path
    path=$(output-directory)/$(printf '%s\n' "${new_components[@]}" | paste -sd"$PATH_SEPARATOR")
    mkdir -p "$(dirname "$path")"
    echo "$path"
}

# returns a file with a given extension for the output of a given stage
output-file(extension, stage=) {
    echo "$(output-directory "$stage")/$DOCKER_OUTPUT_FILE_PREFIX.$extension"
}

# standard files for experimental results, human-readable output, and human-readable errors
input-csv() { input-file csv; }
input-log() { input-file log; }
input-err() { input-file err; }
output-csv(stage=) { output-file csv "$stage"; }
output-log(stage=) { output-file log "$stage"; }
output-err(stage=) { output-file err "$stage"; }

# returns whether the given experiment stage is done
stage-done(stage) {
    require-host
    [[ -d $(output-directory "$stage") ]]
}

# requires that he given experiment stage is done
require-stage-done(stage) {
    require-host
    if ! stage-done "$stage"; then
        error "Stage $stage not done yet, please run stage $stage."
    fi
}
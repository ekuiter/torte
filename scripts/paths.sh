#!/bin/bash

# returns the root input directory
input-directory() {
    if [[ -z $DOCKER_RUNNING ]]; then
        echo "$INPUT_DIRECTORY"
    else
        echo "$DOCKER_INPUT_DIRECTORY"
    fi
}

# returns the directory for all outputs for a given stage
output-directory(stage=) {
    if [[ -z $DOCKER_RUNNING ]]; then
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
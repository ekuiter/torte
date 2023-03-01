#!/bin/bash
# main entry point, runs whatever functions it is passed
# behaves differently if run inside Docker by relying on the docker_running environment variable
# example: ./main.sh clean run

set -e # exit on error
shopt -s expand_aliases # enable aliases
trap "echo ERROR! >&2" ERR # set error handler

scripts_directory=$(dirname "$0") # scripts directory
docker_input_directory=/home/input # input directory inside Docker containers
docker_output_directory=/home/output # output directory inside Docker containers
docker_output_file_prefix=output # prefix for output files inside Docker containers
models_output_directory=models # output directory for storing kconfig models
c_bindings_output_directory=c-bindings # output directory for storing C bindings

source $scripts_directory/helpers.sh # miscellaneous helpers
source $scripts_directory/paths.sh # functions for dealing with input/output paths
source $scripts_directory/experiment.sh # functions for running stages and loading experiments
source $scripts_directory/extraction.sh # functions for extracting kconfig models

# runs all functions that are given as arguments
if [[ ! -z "$@" ]]; then
    for command in "$@"; do
        $command
    done
fi
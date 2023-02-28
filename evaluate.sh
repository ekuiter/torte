#!/bin/bash
set -e # exit on error
shopt -s expand_aliases # enable aliases
trap "echo ERROR! >&2" ERR # set error handler
cd "$(dirname "$0")" # change working directory into script directory

docker_input_directory=input # input directory inside Docker containers
docker_output_directory=output # output directory inside Docker containers
docker_output_file_prefix=output # prefix for output files inside Docker containers

# echos and appends to a file
alias append="tee -a"

# logs an error and exit
error() {
    echo "$@" 1>&2
    exit 1
}

# requires that the given commands are available
require-command() {
    for command in $@; do
        if ! command -v $command &> /dev/null; then
            error "Required command $command is missing, please install manually."
        fi
    done
}

# requires that the given variables are set
require-variable() {
    for var in $@; do
        if [[ -z ${!var+x} ]]; then
            error "Required variable $var is not set, please set it to some value."
        fi
    done
}

# requires that the given variables are non-empty
require-value() {
    for var in $@; do
        if [[ -z ${!var} ]]; then
            error "Required variable $var is empty, please set it to a non-empty value."
        fi
    done
}

# requires that we are not in a Docker container
require-host() {
    if [[ ! -z $docker_running ]]; then
        error "Cannot be run inside a Docker container."
    fi
}

# returns whether a function is not defined, useful for providing fallback implementations
unless-function() { ! declare -F $1 >/dev/null; }

# replaces a given search string for a given number of times per line
replace-times() {
    local n=$1
    local search=$2
    local replace=$3
    require-value n search replace
    if [[ $n -eq 0 ]]; then
        cat -
    else
        cat - | sed "s/$search/$replace/" | replace-times $(($n-1)) $search $replace
    fi
}

# joins two CSV files on the first n columns, assumes that the first line contains a header
join-tables() {
    local a=$1
    local b=$2
    local n=${3:-1}
    ((n--))
    require-value a b
    cat $a | replace-times $n , \# > $a.tmp
    cat $b | replace-times $n , \# > $b.tmp
    join -t, \
        <(cat $a.tmp | head -n1) \
        <(cat $b.tmp | head -n1) \
        | replace-times $n \# ,
    join -t, \
        <(cat $a.tmp | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        <(cat $b.tmp | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        | replace-times $n \# ,
    rm $a.tmp
    rm $b.tmp
}

# returns the directory for all outputs for a given stage
output-directory() {
    if [[ -z $docker_running ]]; then
        local stage=$1
        require-value stage
        echo $output_directory/$stage
    else
        echo $docker_output_directory
    fi
}

# returns a prefix for all output files for a given stage
output-prefix() {
    if [[ -z $docker_running ]]; then
        output-directory $1
    else
        echo $docker_output_directory/$docker_output_file_prefix
    fi
}

# returns a file with a given extension for the output of a given stage
output-file() {
    local extension=$1
    local stage=$2
    require-value extension
    echo $(output-prefix $stage).$extension
}

# standard output files
output-csv() { output-file csv $1; } # for experimental results
output-log() { output-file log $1; } # for human-readable output (by default, output of Docker container)
output-err() { output-file err $1; } # for human-readable errors

# moves all output files of a given stage into the root output directory
copy-output-files() {
    local stage=$1
    require-host
    require-value stage
    shopt -s nullglob
    for output_file in $(output-directory $stage)/$docker_output_file_prefix*; do
        local extension=${output_file#*.}
        cp $output_file $(output-file $extension $stage)
    done
    shopt -u nullglob
}

# runs a stage of some experiment in a Docker container
run-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    local command=$4
    require-host
    require-value stage dockerfile input_directory command
    if [[ ! -f $(output-log $stage) ]]; then
        echo "Running stage $stage"
        rm -rf $(output-prefix $stage)*
        if [[ $skip_docker_build != y ]]; then
            local context=$(dirname $dockerfile)
            cp $experiment $context/_experiment.sh
            cp "$0" $context/_evaluate.sh
            docker build -f $dockerfile -t $stage $context
        fi
        mkdir -p $(output-directory $stage)
        docker run --rm \
            -v $PWD/$input_directory:/home/input \
            -v $PWD/$(output-directory $stage):/home/output \
            -e docker_running=y \
            $stage $command \
            > >(append $(output-log $stage)) \
            2> >(append $(output-err $stage) >&2)
        copy-output-files $stage
        rmdir --ignore-fail-on-non-empty $(output-directory $stage)
    else
        echo "Skipping stage $stage"
    fi
}

# loads the given experiment, adding all systems and versions in the process
# on the host, this has no effect besides defining variables and functions
load-experiment() {
    if [[ -z $docker_running ]]; then
        experiment=${1:-input/experiment.sh}
    else
        experiment=${1:-_experiment.sh}
    fi
    if [[ ! -f $experiment ]]; then
        echo "Please provide an experiment file in $experiment."
        exit 1
    fi
    source $experiment
    require-variable experiment input_directory output_directory skip_docker_build
}

# stubs that are implemented in Docker containers and experiment files
unless-function add-system && add-system() { :; } # adds a system to evaluate
unless-function add-version && add-version() { :; } # adds a version to evaluate
unless-function run-experiment && run-experiment() { :; } # runs an experiment

# removes all output files for the given experiment, does not touch input files or Docker images
clean() {
    require-host
    load-experiment $1
    rm -rf $output_directory
}

# runs the given experiment
run() {
    require-host
    require-command docker
    load-experiment $1
    mkdir -p $output_directory
    run-experiment
}

# does nothing, only defines variables and functions
init() { :; }

# runs all functions that are given as arguments
if [[ ! -z "$@" ]]; then
    for command in "$@"; do
        $command
    done
fi
# runs a stage of some experiment in a Docker container
# reads the global config_file variable
run-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    local command=$4
    require-host
    require-value config_file stage dockerfile input_directory
    local flags=
    if [[ -z $command ]]; then
        command=/bin/bash
        flags=-it
    fi
    if [[ ! -f $(output-log $stage) ]]; then
        echo "Running stage $stage"
        rm -rf $(output-prefix $stage)*
        if [[ $skip_docker_build != y ]]; then
            cp $config_file $scripts_directory/_config.sh
            docker build -f $dockerfile -t $stage $scripts_directory
        fi
        mkdir -p $(output-directory $stage)
        docker run --rm $flags \
            -v $PWD/$(input-directory):$docker_input_directory \
            -v $PWD/$(output-directory $stage):$docker_output_directory \
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

# prepares an experimnt by loading the given config file
# adds all experiment subjects in the process
# on the host, this has no effect besides defining variables and functions
# sets several global variables
load() {
    if [[ -z $docker_running ]]; then
        config_file=${1:-input/config.sh}
    else
        config_file=${1:-_config.sh}
    fi
    if [[ ! -f $config_file ]]; then
        echo "Please provide a config file in $config_file."
        exit 1
    fi
    source $config_file
    require-variable config_file input_directory output_directory skip_docker_build
    experiment-subjects
}

# removes all output files specified by the given config file, does not touch input files or Docker images
clean() {
    require-host
    load $1
    rm -rf $output_directory
}

# runs the experiment defined in the given config file
run() {
    require-host
    require-command docker
    load $1
    mkdir -p $output_directory
    experiment-stages
}

# does nothing, only defines variables and functions
init() { :; }

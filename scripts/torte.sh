#!/bin/bash
# main entry point, runs whatever functions it is passed
# behaves differently if run inside Docker by relying on the DOCKER_RUNNING environment variable
# example: ./torte.sh clean run

set -e # exit on error
trap "echo ERROR! >&2" ERR # set error handler

# API functions
api=(
    # implemented in config files
    experiment-stages
    experiment-subjects
    kconfig-post-checkout-hook
    kclause-post-binding-hook

    # implemented in Docker containers
    add-system
    add-revision
    add-kconfig-binding
    add-kconfig-model
    add-kconfig
)

SCRIPTS_DIRECTORY=$(dirname "$0") # scripts directory
DOCKER_PREFIX=torte # prefix for naming Docker images and containers
DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
DOCKER_OUTPUT_FILE_PREFIX=output # prefix for output files inside Docker containers
KCONFIG_MODELS_OUTPUT_DIRECTORY=kconfig-models # output directory for storing kconfig models
KCONFIG_BINDINGS_OUTPUT_DIRECTORY=kconfig-bindings # output directory for storing Kconfig bindings
TRANSIENT_STAGE=transient # name for transient stages

source "$SCRIPTS_DIRECTORY/bootstrap.sh" # modifies bash to allow for succinct function definitions
source "$SCRIPTS_DIRECTORY/helpers.sh" # miscellaneous helpers
source "$SCRIPTS_DIRECTORY/paths.sh" # functions for dealing with input/output paths
source "$SCRIPTS_DIRECTORY/experiment.sh" # functions for running stages and loading experiments
source "$SCRIPTS_DIRECTORY/kconfig.sh" # functions for extracting kconfig models

# prints a banner
banner() {
    echo "$DOCKER_PREFIX" | sed -E s/./=/g
    echo "$DOCKER_PREFIX"
    echo "$DOCKER_PREFIX" | sed -E s/./=/g
    echo
}

# prints help information
help() {
    banner
    echo "usage: $(basename "$0") [command]..."
    echo
    echo "commands:"
    echo "run [config-file]      runs the experiment defined in the given config file (default: input/config.sh)"
    echo "clean [config-file]    removes all output files specified by the given config file (default: input/config.sh)"
    echo "stop                   stops a running experiment"
    echo "help                   prints help information"
}

# define stubs for API functions
for function in "${api[@]}"; do
    define-stub "$function"
done

# run all given functions
if [[ -z "$*" ]]; then
    run ""
else
    for command in "$@"; do
        $command
    done
fi

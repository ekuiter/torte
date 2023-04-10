#!/bin/bash
# main entry point, runs whatever command it is passed
# behaves differently if run inside Docker

set -e # exit on error

# prints help information
command-help() {
    echo "usage: $(basename "$0") [experiment_file] [command [option]...]"
    echo
    echo "experiment_file (default: experiments/default.sh)"
    echo
    echo "command (default: run)"
    echo "  run                 runs the experiment"
    echo "  clean               removes all output files for the experiment"
    echo "  stop                stops the experiment"
    echo "  export [directory]  saves all experiment-related Docker images, input, and output into the given directory"
    echo "  import [directory]  loads all Docker images from the given directory"
    echo "  reset               removes all Docker containers and images"
    echo "  browse              start a web server for browsing output files"
    echo "  help                prints help information"
}

# scripts to include
export SCRIPTS=(
    bootstrap.sh # modifies bash to allow for succinct function definitions
    helper.sh # miscellaneous helpers
    path.sh # deals with input/output paths
    stage.sh # runs stages
    experiment.sh # runs experiments
    docker.sh # functions for working with Docker containers
    utilities.sh # functions for working with Git repositories and other utilities
    extraction.sh # extracts kconfig models
    transformation.sh # transforms files
    initialization.sh # initializes the script
)

# API functions
export API=(
    # implemented in config files
    experiment-stages # defines the stages of the experiment in order of their execution
    experiment-subjects # defines the experiment subjects
    kconfig-post-checkout-hook # called after a system has been checked out during kconfig model extraction
    kmax-post-binding-hook # called after a kconfig binding has been executed during kconfig model extraction

    # implemented in Docker containers
    add-system # adds a system (e.g., clone)
    add-revision # adds a system revision (e.g., read statistics)
    add-kconfig-binding # adds a kconfig binding (e.g., dumpconf or kextractor)
    add-kconfig-model # adds a kconfig model (e.g., a model read by kconfigreader or kmax)
    add-kconfig # adds a kconfig binding and model
)

# configuration options, can optionally be overridden in experiment files
export DOCKER_PREFIX=torte # prefix for naming Docker images and containers
export DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
export DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
export DOCKER_OUTPUT_FILE_PREFIX=output # prefix for output files inside Docker containers
export KCONFIG_MODELS_OUTPUT_DIRECTORY= # output directory for storing kconfig models
export KCONFIG_BINDINGS_OUTPUT_DIRECTORY=kconfig-bindings # output directory for storing Kconfig bindings
export TRANSIENT_STAGE=transient # name for transient stages
export PATH_SEPARATOR=/ # separator for building paths
export INPUT_DIRECTORY=input # path to system repositories
export OUTPUT_DIRECTORY=output # path to resulting outputs, created if necessary
export SKIP_DOCKER_BUILD= # y if building Docker images should be skipped, useful for loading imported images
export MEMORY_LIMIT=$(($(sed -n '/^MemTotal:/ s/[^0-9]//gp' /proc/meminfo)/1024/1024)) # memory limit in GiB for running Docker containers and other tools, should be at least 2 GiB
export FORCE_RUN= # y if every stage should be forced to run regardless of whether is is already done
export VERBOSE= # y if console output should be verbose

export SCRIPTS_DIRECTORY
SCRIPTS_DIRECTORY=$(dirname "$0") # scripts directory
for script in "${SCRIPTS[@]}"; do
    # shellcheck disable=SC1090
    source "$SCRIPTS_DIRECTORY/$script"
done

initialize "$@"
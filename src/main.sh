#!/usr/bin/env bash
# main entry point, runs whatever command it is passed
# behaves differently if run inside Docker
# we need /usr/bin/env so the correct bash version is used on macOS

set -e # exit on error

# prints help information
command-help() {
    echo "usage: $(basename "$0") [experiment_file] [command [option]...]"
    echo
    echo "experiment_file (default: experiments/default.sh)"
    echo
    echo "command (default: run)"
    echo "  run                              runs the experiment"
    echo "  clean                            removes all output files for the experiment"
    echo "  stop                             stops the experiment"
    echo "  reset                            removes all Docker containers and images"
    echo "  export                           prepares a reproduction package"
    echo "  run-remote [host]                runs the experiment on a remote server"
    echo "  copy-remote [host]               downloads results from the remote server"
    echo "  install-remote [host] [image]    installs a Docker image on a remote server"
    echo "  browse                           start a web server for browsing output files"
    echo "  help                             prints help information"
}

# scripts to include
SCRIPTS=(
    helper.sh # miscellaneous helpers
    path.sh # deals with input/output paths
    stage.sh # runs stages
    experiment.sh # runs experiments
    docker.sh # functions for working with Docker containers
    utilities.sh # functions for working with Git repositories and other utilities
    subjects/subjects.sh # configures common experiment subjects
    extraction.sh # extracts kconfig models
    transformation.sh # transforms files
    analysis.sh # analyzes files
    initialization.sh # initializes the script
)

# API functions
API=(
    # implemented in config files
    experiment-stages # defines the stages of the experiment in order of their execution
    experiment-subjects # defines the experiment subjects

    # implemented in Docker containers
    add-system # adds a system (e.g., clone)
    add-revision # adds a system revision (e.g., read statistics)
    add-kconfig-binding # adds a kconfig binding (e.g., dumpconf or kextractor)
    add-kconfig-model # adds a kconfig model (e.g., a model read by kconfigreader or kmax)
    add-kconfig # adds a kconfig binding and model
)

# global configuration options, can optionally be overridden in experiment files
TOOL=torte # tool name, used as prefix for naming Docker images and containers
DOCKER_INPUT_DIRECTORY=/home/input # input directory inside Docker containers
DOCKER_OUTPUT_DIRECTORY=/home/output # output directory inside Docker containers
DOCKER_SCRIPTS_DIRECTORY=/home/${TOOL}_scripts # scripts directory inside Docker containers
DOCKER_OUTPUT_FILE_PREFIX=output # prefix for output files inside Docker containers
KCONFIG_MODELS_OUTPUT_DIRECTORY= # output directory for storing kconfig models
KCONFIG_BINDINGS_OUTPUT_DIRECTORY=kconfig-bindings # output directory for storing Kconfig bindings
TRANSIENT_STAGE=transient # name for transient stages
PATH_SEPARATOR=/ # separator for building paths
INPUT_DIRECTORY=input # path to system repositories
OUTPUT_DIRECTORY=output # path to resulting outputs, created if necessary
SCRIPTS_DIRECTORY=$(dirname "$0") # scripts directory
TOOL_DIRECTORY=$SCRIPTS_DIRECTORY/.. # tool directory
DOCKER_DIRECTORY=$TOOL_DIRECTORY/docker # path to docker files
EXPORT_DIRECTORY=$TOOL_DIRECTORY/export # path for exporting experiments
CACHE_DIRECTORY=.cache # path for cached data in output directory
TOOL_SCRIPT=$TOOL_DIRECTORY/$TOOL.sh # tool script
DOCKER_RUN=${DOCKER_RUN:-y} # y if running Docker containers is enabled, otherwise saves image archives
FORCE_RUN= # y if every stage should be forced to run regardless of whether is is already done
VERBOSE= # y if console output should be verbose
DEBUG= # y for debugging stages interactively
LINUX_CLONE_MODE=fork # clone mode for Linux repository, can be either fork, original, or filter

# memory limit in GiB for running Docker containers and other tools, should be at least 2 GiB
if [[ "$OSTYPE" == "darwin"* ]]; then
    MEMORY_LIMIT=$(($(memory_pressure | head -n1 | cut -d' ' -f4)/1024/1024/1024))
else
    MEMORY_LIMIT=$(($(sed -n '/^MemTotal:/ s/[^0-9]//gp' /proc/meminfo)/1024/1024))
fi

# print banner image (if not already done)
if [[ -z "$TORTE_BANNER_PRINTED" ]]; then
    echo "┌────────────────────────────────────────────────┐"
    echo "│ $TOOL: feature-model experiments à la carte 🍰 │"
    echo "└────────────────────────────────────────────────┘"
    echo
fi

# modify bash to allow for succinct function definitions
source "$SCRIPTS_DIRECTORY/bootstrap.sh"

# load library scripts
for script in "${SCRIPTS[@]}"; do
    source-script "$SCRIPTS_DIRECTORY/$script"
done

# initialize torte and run the given experiment or command
initialize "$@"
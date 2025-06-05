#!/usr/bin/env bash
# main entry point, runs whatever command it is passed
# behaves differently if run inside Docker
# we need /usr/bin/env so the correct Bash version is used on macOS

set -e # exit on error

# global constants, should not be overridden
TOOL=torte # tool name, used as prefix for naming Docker images and containers
SRC_DIRECTORY=$(dirname "$0") # scripts directory
TOOL_DIRECTORY=$SRC_DIRECTORY/.. # tool directory
DOCKER_DIRECTORY=$SRC_DIRECTORY/docker # path to Docker files
EXPORT_DIRECTORY=$TOOL_DIRECTORY/export # path for exporting experiments
TOOL_SCRIPT=$TOOL_DIRECTORY/$TOOL.sh # tool script
DOCKER_RUN=${DOCKER_RUN:-y} # y if running Docker containers is enabled, otherwise saves image archives

# global configuration options, can optionally be overridden in experiment files
OUTPUT_DIRECTORY=output # path to resulting experiment output, created if necessary (should not include ., .., or /)
PATH_SEPARATOR=/ # separator for building paths
FORCE_RUN= # y if every stage should be forced to run regardless of whether is is already done
VERBOSE= # y if console output should be verbose
DEBUG= # y for debugging stages interactively
LINUX_CLONE_MODE=fork # clone mode for Linux repository, can be either fork, original, or filter
MEMORY_LIMIT= # if unset, this is automatically determined in helper/platform.sh

# print banner image (if on host and not already done)
if [[ -z $INSIDE_DOCKER_CONTAINER ]] && [[ -z $TORTE_BANNER_PRINTED ]]; then
    echo "┌────────────────────────────────────────────────┐"
    echo "│ $TOOL: feature-model experiments à la carte 🍰 │"
    echo "└────────────────────────────────────────────────┘"
    echo
fi

# prints help information
command-help() {
    echo
    echo "usage: $TOOL.sh [experiment_file] [command [option]...]"
    echo
    echo "experiment_file (default: default)"
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

# modify Bash to allow for succinct function definitions
source "$SRC_DIRECTORY/bootstrap.sh"

# load all scripts, starting with specific facilities, which are needed right away to enable logging
for script in \
    lib/helper/time.sh \
    lib/helper/log.sh \
    $(find "$SRC_DIRECTORY"/lib -name '*.sh') \
    $(find "$SRC_DIRECTORY"/systems -name '*.sh'); do
    source-script "$script"
done

# initialize torte and run the given experiment or command
entrypoint "$@"
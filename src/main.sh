#!/usr/bin/env bash
# main entry point, runs whatever command it is passed
# behaves differently if run inside Docker
# we need /usr/bin/env so the correct Bash version is used on macOS

set -e # exit on error

# global constants, should not be overridden
TOOL=torte # tool name, used as prefix for naming Docker images and containers
EXPERIMENT_STAGE=experiment # name for the stage directory containing the experiment and logs
ROOT_STAGE=clone-systems # name for the root stage directory that has itself as input
SRC_DIRECTORY=$(dirname "$0") # scripts directory
TOOL_DIRECTORY=$SRC_DIRECTORY/.. # tool directory
DOCKER_DIRECTORY=$SRC_DIRECTORY/docker # path to Docker files
EXPORT_DIRECTORY=$TOOL_DIRECTORY/export # path for exporting experiments
TOOL_SCRIPT=$TOOL_DIRECTORY/$TOOL.sh # tool script

# global configuration options, can optionally be overridden with environment variables or in experiment files
STAGES_DIRECTORY=${STAGES_DIRECTORY:-stages} # path to resulting experiment stages, created if necessary (should not include ., .., or /)
PATH_SEPARATOR=${PATH_SEPARATOR:-/} # separator for building paths
FORCE_RUN=${FORCE_RUN:-} # y if every stage should be forced to run regardless of whether is is already done
FORCE_BUILD=${FORCE_BUILD:-} # y if Docker images should be built without cache
VERBOSE=${VERBOSE:-} # y if console output should be verbose
DEBUG=${DEBUG:-} # y for debugging stages interactively
LINUX_CLONE_MODE=${LINUX_CLONE_MODE:-fork} # clone mode for Linux repository, can be either fork, original, or filter
BUSYBOX_GENERATE_MODE=${BUSYBOX_GENERATE_MODE:-fork} # mode for BusyBox full history generation, can be either fork or generate
MEMORY_LIMIT=${MEMORY_LIMIT:-} # if unset, this is automatically determined in helper/platform.sh

# global configuration options that cannot be overridden in experiment files, but only with environment variables
PROFILE=${PROFILE:-} # y to enable function profiling
TEST=${TEST:-} # y to run experiment for test systems only

# print banner image (if on host and not already done)
if [[ -z $INSIDE_STAGE ]] && [[ -z $TORTE_BANNER_PRINTED ]]; then
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
    echo "  test                             runs tests for all testable experiments"
    echo "  clean                            removes all output files for the experiment"
    echo "  stop                             stops the experiment"
    echo "  uninstall                        removes all Docker containers and images"
    echo "  export                           prepares a reproduction package"
    echo "  run-remote [host]                runs the experiment on a remote server"
    echo "  copy-remote [host]               downloads results from the remote server"
    echo "  install-remote [host] [image]    installs a Docker image on a remote server"
    echo "  browse                           start a web server for browsing output files"
    echo "  help                             prints help information"
}

# modify Bash to allow for succinct function definitions
source "$SRC_DIRECTORY/preprocessor.sh"

# check for profiling mismatch and clean generated files if needed
if [[ -d "$GEN_DIRECTORY" ]]; then
    has_profiling_code=
    if grep -r "__profile_start_time" "$GEN_DIRECTORY" >/dev/null 2>&1; then
        has_profiling_code=y
    fi
    if { [[ -n $has_profiling_code ]] && [[ -z $PROFILE ]]; } || { [[ -z $has_profiling_code ]] && [[ -n $PROFILE ]]; }; then
        rm -rf "$GEN_DIRECTORY"
    fi
fi

# load all scripts, starting with specific facilities, which are needed right away to enable logging
for script in \
    lib/helper/time.sh \
    lib/helper/log.sh \
    $(find "$SRC_DIRECTORY"/lib -name '*.sh') \
    $(find "$SRC_DIRECTORY"/systems -name '*.sh'); do
    source-script "$script"
done

# initialize torte and run the given experiment or command
TOOL_INITIALIZED=y
entrypoint "$@"
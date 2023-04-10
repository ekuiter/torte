#!/bin/bash
# installs and runs torte

set -e
TORTE_REPOSITORY=${TORTE_REPOSITORY:-https://github.com/ekuiter/torte.git}
TORTE_REVISION=${TORTE_REVISION:-main}

if (return 0 2>/dev/null); then
    # if this script is sourced from an experiment file, install into the working directory
    if ! command -v git > /dev/null; then
        echo "Required command git is missing, please install manually."
        exit 1
    fi
    if [[ ! -d torte ]]; then
        echo "===="
        echo "NOTE: torte is not installed yet."
        echo "torte (revision $TORTE_REVISION) will now be installed into the directory '$PWD/torte'."
        echo "By default, all experiment data will be stored in the directories '$PWD/input' and '$PWD/output'."
        echo "===="
        git clone -q "$TORTE_REPOSITORY"
    fi
    git -C torte checkout -q "$TORTE_REVISION"
    torte/torte.sh "$0" "$@" # run main entry point for the given experiment file
    exit 0 # exit the experiment file's parent shell
else
    # if this script is executed directly, run main entry point
    "$(dirname "$0")"/scripts/torte.sh "$@"
fi
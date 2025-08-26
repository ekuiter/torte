#!/bin/bash
# installs and runs torte

set -e
TORTE_REPOSITORY=${TORTE_REPOSITORY:-https://github.com/ekuiter/torte.git}
TORTE_REVISION=${TORTE_REVISION:-main}

require() {
     if ! command -v "$1" > /dev/null; then
        echo "Required command $1 is missing, please install manually." 1>&2
        exit 1
    fi
}

# perform a bit of Bash magic to determine if this script is sourced or executed directly
if (return 0 2>/dev/null); then
    # if this script is sourced from an experiment file, install into the working directory
    require git
    require make
    export TORTE_BANNER_PRINTED=
    if [[ ! -d torte ]]; then
        echo "┌────────────────────────────────────────────────┐"
        echo "│ torte: feature-model experiments à la carte 🍰 │"
        echo "└────────────────────────────────────────────────┘"
        echo
        echo "NOTE: torte is not installed yet."
        echo "torte (revision $TORTE_REVISION) will now be installed into the directory '$PWD/torte'."
        echo "By default, all experiment data will be stored in the directory '$PWD/stages'."
        echo
        git clone --recursive -q "$TORTE_REPOSITORY" 1>/dev/null
        TORTE_BANNER_PRINTED=y # prevent printing the banner again in torte.sh
    fi
    git -C torte checkout --recurse-submodules -q "$TORTE_REVISION" 1>/dev/null
    torte/torte.sh "$0" "$@" # run main entry point for the given experiment file ($0 is the sourcing experiment file)
    exit 0 # exit the experiment file's parent shell once done
else
    # if this script is executed directly, run main entry point in src/main.sh
    "$(dirname "$0")"/src/main.sh "$@"
fi
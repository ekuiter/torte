#!/bin/bash

# echos and appends to a file
alias append="tee -a"

# logs an error and exit
error() {
    echo "$@" 1>&2
    exit 1
}

# requires that the given commands are available
require-command() {
    for command in "$@"; do
        if ! command -v "$command" &> /dev/null; then
            error "Required command $command is missing, please install manually."
        fi
    done
}

# requires that the given variables are set
require-variable() {
    for var in "$@"; do
        if [[ -z ${!var+x} ]]; then
            error "Required variable $var is not set, please set it to some value."
        fi
    done
}

# requires that the given variables are non-empty
require-value() {
    for var in "$@"; do
        if [[ -z ${!var} ]]; then
            error "Required variable $var is empty, please set it to a non-empty value."
        fi
    done
}

# requires that we are not in a Docker container
require-host() {
    if [[ -n $DOCKER_RUNNING ]]; then
        error "Cannot be run inside a Docker container."
    fi
}

# returns whether a function is not defined, useful for providing fallback implementations
unless-function() { ! declare -F "$1" >/dev/null; }

# if not defined, defines a function with a given name doing nothing
define-stub() {
    function=$1
    require-value function
    eval "unless-function $function && $function() { :; } || true"
}

# replaces a given search string for a given number of times per line, operates on standard input
replace-times() {
    local n=$1
    local search=$2
    local replace=$3
    require-value n search replace
    if [[ $n -eq 0 ]]; then
        cat -
    else
        cat - | sed "s/$search/$replace/" | replace-times $((n-1)) "$search" "$replace"
    fi
}

# joins two CSV files on the first n columns, assumes that the first line contains a header
join-tables() {
    local a=$1
    local b=$2
    local n=${3:-1}
    ((n--))
    require-value a b
    join -t, \
        <(replace-times $n , \# < "$a" | head -n1) \
        <(replace-times $n , \# < "$b" | head -n1) \
        | replace-times $n \# ,
    join -t, \
        <(replace-times $n , \# < "$a" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        <(replace-times $n , \# < "$b" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        | replace-times $n \# ,
}

# silently push directory
push() {
    pushd "$@" > /dev/null || error "Failed to push directory $*."
}

# silently pop directory
pop() {
    popd > /dev/null || error "Failed to pop directory."
}

# remove (un-)staged changes and untracked files
git-clean() {
    local directory=${1:-.}
    require-value directory
    git -C "$directory" reset -q --hard >/dev/null
    git -C "$directory" clean -q -dfx > /dev/null
}

# clean and checkout a revision
git-checkout() {
    local revision=$1
    local directory=$2
    require-value revision directory
    echo "Checking out $revision in $directory"
    git-clean "$directory"
    git -C "$directory" checkout -q -f "$revision" > /dev/null
}

# list all revisions in version order
git-revisions() {
    local system=$1
    require-value system
    git -C "$(input-directory)/$system" tag | sort -V
}

# exclude revisions matching a term
exclude-revision() {
    local term=$1
    shift
    if [[ -z $term ]]; then
        cat -
    else
        cat - | grep -v "$term" | exclude-revision "$@"
    fi
}

# only include revisions starting from a given revision
start-at-revision() {
    local start_inclusive=$1
    if [[ -z $start_inclusive ]]; then
        cat -
    else
        sed -n '/'"$start_inclusive"'/,$p'
    fi
}

# only include revisions starting up to a given revision
stop-at-revision() {
    local end_exclusive=$1
    if [[ -z $end_exclusive ]]; then
        cat -
    else
        sed -n '/'"$end_exclusive"'/q;p'
    fi
}
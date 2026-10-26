#!/bin/bash
# platform-specific adjustments and helper functions
# we cannot profile some of these functions, as they are needed for profiling itself

has-command(__NO_PROFILE__, command) {
    command -v "$command" > /dev/null
}

# asserts that the given commands are available
assert-command(__NO_PROFILE__, commands...) {
    local command
    for command in "${commands[@]}"; do
        if ! has-command "$command"; then
            error "Required command $command is missing, please install manually."
        fi
    done
}

# returns whether the processor architecture is ARM
is-arm() {
    [[ $(uname -m) == arm64 ]] || [[ $(uname -m) == aarch64 ]]
}

# returns whether the operating system is macOS
is-macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

# use gsed and ggrep on macOS
if is-macos; then
    sed(args...) {
        assert-command gsed
        gsed "${args[@]}"
    }

    grep(args...) {
        assert-command ggrep
        ggrep "${args[@]}"
    }

    cut(args...) {
        assert-command gcut
        gcut "${args[@]}"
    }

    date(__NO_PROFILE__, args...) {
        assert-command gdate
        gdate "${args[@]}"
    }
fi

# define default memory limit (in GiB) for running Docker containers and other tools (should be at least 2 GiB)
if [[ -z $MEMORY_LIMIT ]]; then
    if is-macos; then
        MEMORY_LIMIT=$(($(memory_pressure | head -n1 | cut -d' ' -f4)/1024/1024/1024))
    else
        MEMORY_LIMIT=$(($(sed -n '/^MemTotal:/ s/[^0-9]//gp' /proc/meminfo)/1024/1024))
    fi
fi

# returns the memory limit, optionally adding a further limit
memory-limit(further_limit=0) {
    echo "$((MEMORY_LIMIT-further_limit))"
}

# returns whether we are in a testing environment
is-testing() {
    [[ -n $TEST ]]
}

# returns whether the experiment has multiple passes
# passes are basically sub-experiments, which allow for more fine-grained control over the experiment
# to use this feature, an experiment must define an array PASSES with the pass names
# passes cannot interact with each other, as they run in separated tool instances
is-multi-pass() {
    [[ ${#PASSES[@]} -gt 0 ]]
}

# returns whether the given pass is active
in-pass(pass) {
    [[ -n $PASS && $PASS == "$pass" ]]
}

# returns whether the first pass of a multi-pass experiment is active
in-first-pass() {
    is-multi-pass && in-pass "${PASSES[0]}"
}

# returns the first pass of a multi-pass experiment
first-pass() {
    if ! is-multi-pass; then
        error "first-pass requires a multi-pass experiment."
    fi
    echo "${PASSES[0]}"
}

# returns the pass immediately preceding the active pass
previous-pass() {
    if [[ -z $PASS ]] || ! is-multi-pass; then
        error "previous-pass requires an active pass of a multi-pass experiment."
    fi
    local i
    for ((i=0; i<${#PASSES[@]}; i++)); do
        if [[ ${PASSES[i]} == "$PASS" ]]; then
            if [[ $i -eq 0 ]]; then
                error "Pass $PASS has no previous pass."
            fi
            echo "${PASSES[i-1]}"
            return
        fi
    done
    error "Pass $PASS is not listed in PASSES."
}

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
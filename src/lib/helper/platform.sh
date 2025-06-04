#!/bin/bash
# platform-specific helper functions

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
        require-command gsed
        gsed "${args[@]}"
    }

    grep(args...) {
        require-command ggrep
        ggrep "${args[@]}"
    }

    cut(args...) {
        require-command gcut
        gcut "${args[@]}"
    }

    date(args...) {
        require-command gdate
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
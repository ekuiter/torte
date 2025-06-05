#!/bin/bash
# helper functions related to the Docker host environment

# returns whether we are in a Docker container
is-host() {
    [[ -z $INSIDE_DOCKER_CONTAINER ]]
}

# returns whether Docker is running
is-docker-running() {
    docker info >/dev/null 2>&1
}

# returns whether we are in rootless mode
is-docker-rootless() {
    docker info -f "{{println .SecurityOptions}}" | grep -q rootless
}

# asserts that we are not in a Docker container
assert-host() {
    if ! is-host; then
        error "Cannot be run inside a Docker container."
    fi
    assert-command docker make
    if ! is-docker-running; then
        error "Docker is not running. Depending on whether rootless mode is enabled, run $TOOL as a normal user or root (e.g., drop or add 'sudo')."
    fi
    if is-macos; then
        return
    fi
    if [[ $(whoami) == root ]] && is-docker-rootless; then
        error "Docker is running in rootless mode (see https://docs.docker.com/engine/security/rootless/). Please do not run $TOOL as root (e.g., drop 'sudo')."
    elif [[ $(whoami) != root ]] && ! is-docker-rootless; then
        error "Docker is not running in rootless mode (see https://docs.docker.com/engine/security/rootless/). Please run $TOOL as root (e.g., use 'sudo')."
    fi
}

# asserts that we are in a Docker container
assert-container() {
    if is-host; then
        error "Cannot be run outside a Docker container."
    fi
}

# logs a message on the Docker host environment
log-host(arguments...) {
    if is-host; then
        log "${arguments[@]}"
    fi
}
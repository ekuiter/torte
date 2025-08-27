#!/bin/bash
# functions for working with Docker containers

DOCKER_EXPORT= # empty if running Docker containers is enabled, otherwise saves image archives

# returns all experiment-related Docker containers
containers() {
    readarray -t containers < <(docker ps -a | tail -n+2 | awk '$2 ~ /^'"$TOOL"'_/ {print $1}')
    echo "${containers[@]}"
}

# returns all experiment-related Docker images
images() {
    readarray -t images < <(docker images -a | tail -n+2 | awk '{if ($1 ~ "^'"$TOOL"'") print $1":"$2}')
    echo "${images[@]}"
}

# returns all dangling Docker images
dangling-images() {
    readarray -t dangling_images < <(docker images -a | tail -n+2 | awk '{if ($1 ~ "^'"$TOOL"'") print $1":"$2}')
    echo "${dangling_images[@]}"
}

# prepares a reproduction package
# exporting all data makes the reproduction package bigger, but has no network dependencies
command-export(experiment=, images=, tool=, stages=, archive=) {
    assert-command tar git
    rm-safe "$EXPORT_DIRECTORY"
    mkdir -p "$EXPORT_DIRECTORY"
    if [[ -n $experiment ]]; then
        cp -R "$SRC_EXPERIMENT_DIRECTORY/" "$EXPORT_DIRECTORY"
    fi
    # shellcheck disable=SC2128
    if [[ -n $images ]]; then
        DOCKER_EXPORT=y
        command-clean
        command-run
        command-clean
    fi
    if [[ -n $tool ]]; then
        git clone --recursive "$TOOL_DIRECTORY" "$EXPORT_DIRECTORY/$TOOL"
        if [[ $tool == *.tar.gz ]]; then
            push "$EXPORT_DIRECTORY"
            tool=$PWD/$tool
            push "$TOOL"
            # shellcheck disable=2035
            tar czvf "$tool" *
            pop
            rm-safe "$TOOL"
            pop
        fi
    fi
    if [[ -n $stages ]]; then
        cp -R "$(stages-directory)" "$EXPORT_DIRECTORY"
    fi
    if [[ -n $archive ]]; then
        archive=$PWD/$archive
        push "$EXPORT_DIRECTORY"
        # shellcheck disable=2035
        tar czvf "$archive" *
        pop
        rm-safe "$EXPORT_DIRECTORY"
    fi
}

# removes all Docker containers and images
command-uninstall() {
    echo "This will remove ALL Docker containers and images related to $TOOL."
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    command-stop
    readarray -t containers < <(docker ps -a | tail -n+2 | awk '$2 ~ /^'"$TOOL"'_/ {print $1}')
    for container in $(containers); do
        docker rm -f "$container"
    done
    for image in $(images); do
        docker rmi -f "$image"
    done
    for image in $(dangling-images); do
        docker rmi -f "$image"
    done
    echo "Success. Consider to run 'docker system prune' manually (which may remove artifacts unrelated to $TOOL)."
}

# start a web server for browsing output files
command-browse() {
    local database_file
    database_file=$(mktemp)
    chmod 0777 "$database_file"
    docker run \
        -v "$(stages-directory):/srv" \
        -v "$database_file:/database.db" \
        -u "$(id -u):$(id -g)" \
        -p 8080:80 \
        -it --entrypoint /bin/sh \
        filebrowser/filebrowser \
        -c "/filebrowser config init; /filebrowser config set --auth.method=noauth; /filebrowser"
    rm-safe "$database_file"
}
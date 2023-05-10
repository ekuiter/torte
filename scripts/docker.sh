#!/bin/bash

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

# prepares a replication package
# exporting all data makes the replication package bigger, but has no network dependencies
command-export(file=experiment.tar.gz, include_images=, include_input=, include_scripts=) {
    require-command tar git
    rm-safe "$EXPORT_DIRECTORY" "$file"
    mkdir -p "$EXPORT_DIRECTORY"
    cp "$SCRIPTS_DIRECTORY/_experiment.sh" "$EXPORT_DIRECTORY"
    if [[ $include_images == y ]]; then
        DOCKER_RUN=
        command-clean
        command-run
        command-clean
    fi
    if [[ $include_input == y ]]; then
        cp -R input "$EXPORT_DIRECTORY"
    fi
    if [[ $include_scripts == y ]]; then
        git clone "$TOOL_DIRECTORY" "$EXPORT_DIRECTORY/$TOOL"
    fi
    file=$PWD/$file
    push "$EXPORT_DIRECTORY"
    # shellcheck disable=2035
    tar czvf "$file" *
    pop
    rm-safe "$EXPORT_DIRECTORY"
}

# removes all Docker containers and images
command-reset() {
    stop-experiment
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
}

# start a web server for browsing output files
command-browse() {
    local database_file
    database_file=$(mktemp)
    chmod 0777 "$database_file"
    docker run \
        -v "$OUTPUT_DIRECTORY:/srv" \
        -v "$database_file:/database.db" \
        -u "$(id -u):$(id -g)" \
        -p 8080:80 \
        -it --entrypoint /bin/sh \
        filebrowser/filebrowser \
        -c "/filebrowser config init; /filebrowser config set --auth.method=noauth; /filebrowser"
    rm-safe "$database_file"
}
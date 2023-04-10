#!/bin/bash

# returns all experiment-related Docker containers
containers() {
    readarray -t containers < <(docker ps -a | tail -n+2 | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
    echo "${containers[@]}"
}

# returns all experiment-related Docker images
images() {
    readarray -t images < <(docker images -a | tail -n+2 | awk '{if ($1 ~ "^'"$DOCKER_PREFIX"'") print $1":"$2}')
    echo "${images[@]}"
}

# returns all dangling Docker images
dangling-images() {
    readarray -t dangling_images < <(docker images -a | tail -n+2 | awk '{if ($1 ~ "^'"$DOCKER_PREFIX"'") print $1":"$2}')
    echo "${dangling_images[@]}"
}

# exports all experiment-related Docker images, input, and output
command-export(directory=export) {
    require-command gzip
    mkdir -p "$directory"
    for image in $(images); do
        docker save "$image" | gzip > "export/$image.tar.gz"
    done
    cp -R ./*.sh "$SCRIPTS_DIRECTORY" "$(input-directory)" "$OUTPUT_DIRECTORY" export/
}

# imports all Docker images in the given directory
command-import(directory=export) {
    for image_file in "$directory"/*.tar.gz; do
        docker load -i "$image_file"
    done
}

# removes all Docker containers and images
command-reset() {
    stop-experiment
    readarray -t containers < <(docker ps -a | tail -n+2 | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
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
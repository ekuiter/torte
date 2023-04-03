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

# saves all experiment-related Docker images, input, and output
save(directory=export) {
    require-command gzip
    mkdir -p "$directory"
    for image in $(images); do
        docker save "$image" | gzip > "export/$image.tar.gz"
    done
    cp -R ./*.sh "$SCRIPTS_DIRECTORY" "$(input-directory)" "$OUTPUT_DIRECTORY" export/
}

# loads all Docker images in the given directory
load(directory=export) {
    for image_file in "$directory"/*.tar.gz; do
        docker load -i "$image_file"
    done
}

# removes all Docker containers and images
uninstall() {
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

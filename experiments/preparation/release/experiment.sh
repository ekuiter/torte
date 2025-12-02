#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment prepares a new release of the tool for uploading on GitHub.
# Builds and collects all Docker images, each of which can be uploaded individually.
# (to circumvent GitHub 2 GiB file limit for releases, and to allow users to only select the images they need).
# Make sure to run this on a Linux machine (not macOS) to make sure the images are built for the linux/amd64 platform.
# The built images are collected in the 'release' directory, together with a copy of the tool distribution.
# To load any of these images on a fresh system (instead of building them from scratch), just place the .tar.gz files in the tool directory (besides the README.md file).
# Using this mechanism ensures the best reproducibility that is possible in our context:
# Given an experiment file, a tool distribution, and all necessary Docker images, the exact experiment environment can be recreated.
# No additional internet connection is needed, only a basic working environment that fulfills the requirements sketched in the README.md file.

EXPORT_DIRECTORY=release

experiment-systems() {
    :
}

experiment-stages(__NO_SILENT__) {
    # when creating a new release, make sure to:
    # - update CHANGELOG.md
    # - git commit and git push
    # - check if CI passes
    # - git tag and git push -t
    # - run this experiment on a Linux machine
    # - create a release on GitHub and upload the images in 'release'

    # make sure we are running in export mode
    if [[ -z $DOCKER_EXPORT ]]; then
        TORTE_BANNER_PRINTED=y "$TOOL_SCRIPT" "$SRC_EXPERIMENT_FILE" export --images y
        exit
    fi

    # export all Docker images
    for docker_path in "$SRC_DIRECTORY/docker"/*/; do
        [[ -d "$docker_path" ]] || continue
        local image
        image="$(basename "$docker_path")"
        run --image "$image" --output "$image"
    done
}
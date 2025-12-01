#!/bin/bash

# adds a single Kconfig file (useful for testing) as a system by creating a temporary git repository
# because our file is not accompanied by any LKC toolchain, we choose a recent version of Linux's LKC implementation
add-kconfig-payload-file(payload_file, system=file, lkc_revision=v6.17, only_configfix=) {
    local url lkc_binding_file
    url=$(mktemp -d)
    cp -R "$SRC_EXPERIMENT_DIRECTORY/$payload_file" "$url/$payload_file"
    add-hook-step pre-clone-hook pre-clone-hook-payload-file
    add-system --system "$system" --url "$url"
    add-revision --system "$system" --revision HEAD
    # this is a little performance hack to skip cloning and checking out Linux when we only want to use ConfigFix
    # as this abstraction level does not know about extractors, we must pass this manually as a parameter if desired
    # not passing the parameter always works, but it can save some time if we only intend to extract with ConfigFix
    if [[ -n $only_configfix ]]; then
        lkc_binding_file=$(none)
    else
        add-linux-lkc-binding --revision "$lkc_revision"
        lkc_binding_file=$(linux-lkc-binding-file "$lkc_revision")
    fi
    add-kconfig-model \
        --system "$system" \
        --revision HEAD \
        --kconfig-file "$payload_file" \
        --lkc-directory "$(none)" \
        --lkc-binding-file "$lkc_binding_file"
}

# prepares a temporary git repository containing the payload file
# only executed in clone-systems stage to avoid recreating the repository in other stages
pre-clone-hook-payload-file(system, url) {
    git -C "$url" init
    git -C "$url" add -A
    git -C "$url" commit -m .
}

# injects a payload file into a stage, typically a UVL (or otherwise parseable) feature-model file
# by default, this injects into the extraction stage, allowing to sidestep Kconfig extraction
# this is useful for experiments that do not involve Kconfig at all
# this function can be called flexibly in experiment-stages wherever needed
# so it could also be used to inject into transformation or solving stages
inject-payload-file(payload_file, stage=extract-kconfig-models, file_column=model_file) {
    if [[ -n $file_column ]]; then
        local csv_line
        csv_line=$(table-construct-row "$(stage-csv "$stage")" "$file_column" "$payload_file")
        csv_line="echo '$csv_line' >> $DOCKER_INPUT_DIRECTORY/$MAIN_INPUT_KEY/$OUTPUT_FILE_PREFIX.csv"
    fi
    run-transient-unless "$stage/$payload_file" \
        "$stage" \
        "$csv_line" \
        "cp \$SRC_EXPERIMENT_DIRECTORY/$payload_file $DOCKER_INPUT_DIRECTORY/$MAIN_INPUT_KEY/$payload_file"
}

# this implements the same functionality as inject-payload-file, but can be called from experiment-systems
# this is a bit less flexible than calling inject-payload-file from experiment-stages, but more intuitive
# sets the global PAYLOAD_FILE_INDEX variable (to track the number of injected payload files)
inject-payload-files-after-extraction() {
    PAYLOAD_FILE_INDEX=0
    add-model-payload-file(payload_file) {
        local payload_file_path
        payload_file_path="$(input-path "$MAIN_INPUT_KEY" "$payload_file")"
        if is-file-empty "$payload_file_path"; then
            table-construct-row "$(input-csv)" model_file "$payload_file" >> "$(input-csv)"
            cp "$SRC_EXPERIMENT_DIRECTORY/$payload_file" "$payload_file_path"
        fi
        PAYLOAD_FILE_INDEX=$((PAYLOAD_FILE_INDEX + 1))
    }
    experiment-systems
    echo "$PAYLOAD_FILE_INDEX" > "$(input-path "$MAIN_INPUT_KEY" .payload_files_injected)"
}
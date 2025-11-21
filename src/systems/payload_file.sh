#!/bin/bash

# adds a single Kconfig file (useful for testing) as a system by creating a temporary git repository
# because our file is not accompanied by any LKC toolchain, we choose a recent version of Linux's LKC implementation
add-kconfig-payload-file(payload_file, system=file, lkc_revision=v6.17) {
    local url
    url=$(mktemp -d)
    cp -R "$SRC_EXPERIMENT_DIRECTORY/$payload_file" "$url/$payload_file"
    git -C "$url" init
    git -C "$url" add -A
    git -C "$url" commit -m .
    add-linux-lkc-binding --revision "$lkc_revision"
    add-system --system "$system" --url "$url"
    add-revision --system "$system" --revision HEAD
    add-kconfig-model \
        --system "$system" \
        --revision HEAD \
        --kconfig-file "$payload_file" \
        --lkc-binding-file "$(linux-lkc-binding-file "$lkc_revision")"
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
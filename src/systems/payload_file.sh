#!/bin/bash

# adds a single Kconfig file (useful for testing) as a system by creating a temporary git repository
# because our file is not accompanied by any LKC toolchain, we choose a recent version of Linux's LKC implementation
add-payload-file-kconfig(payload_file, system=file, lkc_revision=v6.17) {
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

# injects a payload file into a stage
inject-payload-file(stage, payload_file, csv_line=) {
    if [[ -n $csv_line ]]; then
        csv_line="echo '$csv_line' >> $DOCKER_INPUT_DIRECTORY/$MAIN_INPUT_KEY/$OUTPUT_FILE_PREFIX.csv"
    fi
    run-transient-unless "$stage/$payload_file" \
        "$stage" \
        "cp \$SRC_EXPERIMENT_DIRECTORY/$payload_file $DOCKER_INPUT_DIRECTORY/$MAIN_INPUT_KEY/$payload_file" \
        "$csv_line"
}

# injects a UVL (or otherwise supported) feature-model file into a stage
# by default, this injects into the extraction stage, allowing to sidestep Kconfig extraction
# this is useful for experiments that do not involve Kconfig at all
inject-feature-model(payload_file, stage=extract-kconfig-models, file_column=model_file) {
    local csv_line
    csv_line=$(table-construct-row "$(stage-csv "$stage")" "$file_column" "$payload_file")
    inject-payload-file --stage "$stage" --payload-file "$payload_file" --csv-line "$csv_line"
}

# injects several feature-model files into a stage (extraction by default)
inject-feature-models(stage=, file_column=, payload_files...) {
    for payload_file in "${payload_files[@]}"; do
        inject-feature-model --payload-file "$payload_file" --stage "$stage" --file-column "$file_column"
    done
}
#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    if [[ $PASS -eq 1 ]]; then
        add-busybox-kconfig-history --from 1_3_0 --to 1_36_1
    elif [[ $PASS -eq 2 ]]; then
        add-busybox-kconfig-history-full
    elif [[ $PASS -eq 3 ]]; then
        add-axtls-kconfig-history --from release-1.0.0 --to release-2.0.0
    elif [[ $PASS -eq 4 ]]; then
        add-uclibc-ng-kconfig-history --from v1.0.2 --to v1.0.40
    elif [[ $PASS -eq 5 ]]; then
        add-toybox-kconfig-history --from 0.4.5 --to 0.8.9
    elif [[ $PASS -eq 6 ]]; then
        add-embtoolkit-kconfig-history --from embtoolkit-1.0.0 --to embtoolkit-1.8.0
    fi
}

experiment-stages() {
    clone-systems
    if [[ $PASS -eq 2 ]]; then
        generate-busybox-models
    fi
    read-statistics
    extract-kconfig-models-with --extractor kmax
    join-into read-statistics kconfig
    build-image clausy
}

# can be executed from output directory to copy and rename model files
copy-models() {
    shopt -s globstar
    mkdir -p models
    for f in kconfig/**/*.model; do
        local revision
        local original_revision
        revision=$(basename "$f" .model | cut -d'[' -f1)
        original_revision=$(basename "$f" .model | cut -d'[' -f2 | cut -d']' -f1)
        cp "$f" "models/$(date -d "@$(grep -E "^$revision," < read-statistics/output.csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$original_revision.model"
    done
    shopt -u globstar
    # shellcheck disable=SC2207,SC2012
    f=($(ls models/*.model | sort -V | tr '\n' ' '))
    for ((i = 0; i < ${#f[@]}-1; i++)); do
        if diff -q "${f[i]}" "${f[i+1]}" >/dev/null; then
            echo "${f[i]}" and "${f[i+1]}" are duplicate >&2
        fi
    done
}

# analyzes differences between model files
batch-diff() {
    run \
        --stage diff \
        --image clausy \
        --input-directory output/models \
        --command run-clausy-batch-diff \
        --timeout 1800
}

# runs all passes automatically and collects results
if [[ -z $PASS ]]; then
    command-run() {
        rm-safe output_all
        for i in $(seq 6); do
            export PASS=$i
            command-clean
            rm-safe "${OUTPUT_DIRECTORY}_$PASS"
            "$TOOL_SCRIPT" "$SCRIPTS_DIRECTORY/_experiment.sh"
            if [[ $DOCKER_RUN != y ]]; then
                return
            fi
            push "$OUTPUT_DIRECTORY"
            copy-models
            pop
            batch-diff
            mkdir -p output_all
            cp "$(output-csv diff)" "output_all/diff_$PASS.csv"
            mv "$OUTPUT_DIRECTORY" "${OUTPUT_DIRECTORY}_$PASS"
        done
    }
fi
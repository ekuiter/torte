#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=eb91ce7; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    if [[ $PASS -eq 1 ]]; then
        add-busybox-kconfig-history --from 1_3_0 --to 1_37_0
    elif [[ $PASS -eq 2 ]]; then
        add-busybox-kconfig-history-full
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
    transform-models-with-featjar --input-stage model --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-models-into-dimacs --input-stage model --timeout "$TIMEOUT"
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

# runs all passes automatically and collects results
if [[ -z $PASS ]]; then
    command-run() {
        for i in $(seq 2); do
            export PASS=$i
            command-clean
            rm-safe "${OUTPUT_DIRECTORY}_$PASS"
            "$TOOL_SCRIPT" "$SCRIPTS_DIRECTORY/_experiment.sh"
            mv "$OUTPUT_DIRECTORY" "${OUTPUT_DIRECTORY}_$PASS"
        done
    }
fi
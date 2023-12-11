#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    if [[ $PASS -eq 1 ]]; then
        #add-busybox-kconfig-history --from 1_3_0 --to 1_37_0
        add-busybox-kconfig-history --from 1_35_0 --to 1_37_0
    elif [[ $PASS -eq 2 ]]; then
        add-busybox-kconfig-history-full
    fi
}

experiment-stages() {
    if [[ -z $PASS ]]; then
        error "Please specify which pass to run."
    fi
    clone-systems
    if [[ $PASS -eq 2 ]]; then
        generate-busybox-models
    fi
    read-statistics
    extract-kconfig-models-with --extractor kmax
    join-into read-statistics kconfig
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

# can be executed from output directory to analyze differences between model files (see GitHub link for installation requirements)
batch-diff() {
    if [[ ! -d clausy ]]; then
        git clone https://github.com/ekuiter/clausy.git
        make -C clausy
    fi
    clausy/scripts/batch_diff.sh models > diff.csv
}

# runs all passes automatically and collects results
run-all() {
    mkdir -p output_all
    for i in $(seq 2); do
        command-clean
        export PASS=$i
        "$TOOL_SCRIPT" "$SCRIPTS_DIRECTORY/_experiment.sh"
        push "$OUTPUT_DIRECTORY"
        copy-models
        batch-diff
        cp diff.csv "../output_all/diff_$PASS.csv"
        pop
        mv "$OUTPUT_DIRECTORY" "${OUTPUT_DIRECTORY}_$PASS"
    done
}
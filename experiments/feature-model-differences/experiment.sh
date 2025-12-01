#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Extraction and comparison of all feature models of several feature-model histories

PASSES=(busybox-releases busybox-commits axtls uclibc-ng toybox embtoolkit)

experiment-systems() {
    case "$PASS" in
        busybox-releases) add-busybox-kconfig-history --from 1_3_0 --to 1_36_1 ;;
        busybox-commits) add-busybox-kconfig-history-commits ;;
        axtls) add-axtls-kconfig-history --from release-1.0.0 --to release-2.0.0 ;;
        uclibc-ng) add-uclibc-ng-kconfig-history --from v1.0.2 --to v1.0.40 ;;
        toybox) add-toybox-kconfig-history --from 0.4.5 --to 0.8.9 ;;
        embtoolkit) add-embtoolkit-kconfig-history --from embtoolkit-1.0.0 --to embtoolkit-1.8.0 ;;
    esac
}

experiment-stages() {
    clone-systems
    [[ "$PASS" == "busybox-commits" ]] && generate-busybox-models
    read-statistics
    extract-kconfig-models --with-kclause y
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
        cp "$f" "models/$(date -d "@$(grep -E "^$revision," < read-statistics/"$OUTPUT_FILE_PREFIX".csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$original_revision.model"
    done
    # shellcheck disable=SC2207,SC2012
    f=($(ls models/*.model | sort -V | tr '\n' ' '))
    for ((i = 0; i < ${#f[@]}-1; i++)); do
        if diff -q "${f[i]}" "${f[i+1]}" >/dev/null; then
            echo "${f[i]}" and "${f[i+1]}" are duplicate >&2
        fi
    done
    shopt -u globstar
}

# analyzes differences between model files
batch-diff() {
    run \
        --image clausy \
        --input models \
        --output diff \
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
            rm-safe "${STAGE_DIRECTORY}_$PASS"
            "$TOOL_SCRIPT" "$SRC_EXPERIMENT_FILE"
            if [[ -n $DOCKER_EXPORT ]]; then
                return
            fi
            push "$STAGE_DIRECTORY"
            copy-models
            pop
            batch-diff
            mkdir -p output_all
            cp "$(stage-csv diff)" "output_all/diff_$PASS.csv"
            mv "$STAGE_DIRECTORY" "${STAGE_DIRECTORY}_$PASS"
        done
    }
fi
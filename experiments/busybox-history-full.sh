#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-busybox-kconfig-history-full
}

experiment-stages() {
    clone-systems
    generate-busybox-models
    read-statistics
    extract-kconfig-models
    join-into read-statistics kconfig
}

# can be executed from output directory to copy and rename model files
copy-models() {
    mkdir -p models/kconfigreader models/kmax
    for f in kconfig/*/busybox-models/*.model; do
        local extractor
        local revision
        local original_revision
        extractor=$(echo "$f" | cut -d/ -f2)
        revision=$(basename "$f" .model | cut -d'[' -f1)
        original_revision=$(basename "$f" .model | cut -d'[' -f2 | cut -d']' -f1)
        cp "$f" "models/$extractor/$(date -d "@$(grep -E "^$revision," < read-statistics/output.csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$original_revision.model"
    done
    for extractor in kconfigreader kmax; do
        # shellcheck disable=SC2207,SC2012
        f=($(ls models/$extractor/*.model | sort -V | tr '\n' ' '))
        for ((i = 0; i < ${#f[@]}-1; i++)); do
            if diff -q "${f[i]}" "${f[i+1]}" >/dev/null; then
                # todo: remove duplicates if necessary
                echo "${f[i]}" and "${f[i+1]}" are duplicate >&2
            fi
        done
    done
    # todo: install and run clausy in helper function
}
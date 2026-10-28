#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment tests and demonstrates multipass experiment support, in which intermediate
# stage outputs are reused across multiple passes of the experiment.

PASSES=(pass1 pass2 pass3)

experiment-systems() {
    experiment-test-systems
}

experiment-test-systems() {
    if in-pass pass1; then
        add-busybox-kconfig-tags --from 1_37_0 --to 1_38_0
    elif in-pass pass2; then
        add-busybox-kconfig-tags --from 1_37_0 --to 1_37_0
    elif in-pass pass3; then
        add-busybox-kconfig-tags --from 1_38_0 --to 1_38_0
    fi
}

# shellcheck disable=SC2086
experiment-stages() {
    # in multipass experiments, we can reuse intermediate stage outputs from any previous pass to avoid redoing work
    ! in-first-pass && reuse-stage-from-previous-pass --stage clone-systems
    clone-systems
    ! in-first-pass && reuse-stage-from-previous-pass --stage read-statistics
    read-statistics
    # to respect stage-specific experiment-systems(), we must resume the extract-kconfig-models stage
    ! in-first-pass && reuse-stage-from-previous-pass --stage extract-kconfig-models --will-resume y
    extract-kconfig-models --with-kconfigreader y --with-kclause y --with-configfix y

    # we can now apply arbitrary transformations to different sets of extracted models in different passes of the experiment
    in-pass pass1 && transform-to-xml $with_timeout
    in-pass pass2 && transform-to-uvl $with_timeout
    in-pass pass3 && transform-to-dimacs $with_timeout

    return 0
}

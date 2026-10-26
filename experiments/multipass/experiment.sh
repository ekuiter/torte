#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment tests and demonstrates multipass experiment support, in which intermediate
# stage outputs are reused across multiple passes of the experiment.

PASSES=(pass1 pass2 pass3)

experiment-systems() {
    if in-pass pass1; then
        add-busybox-kconfig-tags --from 1_37_0 --to 1_39_0
    elif in-pass pass2; then
        add-busybox-kconfig-tags --from 1_37_0 --to 1_38_0
    elif in-pass pass3; then
        add-busybox-kconfig-tags --from 1_38_0 --to 1_39_0
    fi
}

experiment-test-systems() {
    experiment-systems
}

# shellcheck disable=SC2086
experiment-stages() {
    if ! in-first-pass; then
        # in multipass experiments, we can reuse intermediate stage outputs from any previous pass to avoid redoing work
        reuse-stage-from-pass --stage clone-systems --pass "$(previous-pass)"
    fi
    clone-systems
    if ! in-first-pass; then
        reuse-stage-from-pass --stage read-statistics --pass "$(previous-pass)"
    fi
    read-statistics
    if ! in-first-pass; then
        # to respect stage-specific experiment-systems(), we must resume the extract-kconfig-models stage with --will-resume y
        reuse-stage-from-pass --stage extract-kconfig-models --pass "$(previous-pass)" --will-resume y
    fi
    extract-kconfig-models --with-kconfigreader y --with-kclause y --with-configfix y

    # we can now apply arbitrary transformations to different sets of extracted models in different passes of the experiment
    in-pass pass1 && transform-to-xml $with_timeout
    in-pass pass2 && transform-to-uvl $with_timeout
    in-pass pass3 && transform-to-dimacs $with_timeout

    return 0
}

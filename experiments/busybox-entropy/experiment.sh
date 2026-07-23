#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

experiment-systems() {
    add-busybox-kconfig-tags
}

experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models \
        --with-kclause y \
        --date-prefix "$(date-format time)"
    join-into read-statistics extract-kconfig-models
    transform-to-dimacs --with-z3 y

    # todo: remove the distinction between constrained and unconstrained features
    compute-unconstrained-features
    compute-constrained-features
    solve \
        --kind sharp-sat \
        --query feature-model-cardinality \
        --timeout 60 \
        --jobs 4 \
        --solver_specs emse-2023/ganak,solver,sharp-sat
    solve \
        --kind sharp-sat \
        --query feature-cardinality \
        --input "$(mount-dimacs-input),$(mount-query-sample compute-constrained-features)" \
        --timeout 60 \
        --jobs 4 \
        --query-iterator "$(to-lambda query-dead constrained.features)" \
        --solver_specs emse-2023/ganak,solver,sharp-sat
}

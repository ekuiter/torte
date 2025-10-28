#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# A secondary experiment that evaluates non-winning SAT competition solvers on the Linux kernel.
# We query randomly for core and dead features, as well as partial configurations.

SOLVE_TIMEOUT=1200

add-sat-heritage

experiment-systems() {
    add-linux-system
    add-linux-kconfig-revisions --revisions \
        "$(echo "v2.5.53 v2.6.0 v2.6.10 v2.6.14 v2.6.19 v2.6.23 v2.6.28" \
                "v2.6.32 v2.6.36 v3.1 v3.7 v3.12 v3.18 v4.3 v4.9 v4.14 v4.20" \
                "v5.4 v5.10 v5.15 v6.1 v6.6 v6.12" | tr ' ' '\n')" --architecture x86
}

experiment-stages() {
    clone-systems
    tag-linux-revisions
    read-statistics --option skip-sloc

    extract-kconfig-models-with \
        --extractor kclause \
        --output extract-kconfig-models
    join-into read-statistics extract-kconfig-models

    transform-model-with-featjar \
        --transformer transform-model-to-smt-with-z3 \
        --output-extension smt \
        --jobs 8
    run \
        --image z3 \
        --input transform-model-to-smt-with-z3 \
        --output transform-model-to-dimacs \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 8
    join-into transform-model-to-smt-with-z3 transform-model-to-dimacs
    join-into extract-kconfig-models transform-model-to-dimacs

    # compute two samples: one for backbone (core/dead) queries, one for partial configuration queries
    compute-constrained-features
    for query in backbone partial; do
        if [[ $query == backbone ]]; then
            size=1
            # size=50
            t_wise=1
        elif [[ $query == partial ]]; then
            size=1
            # size=25
            t_wise=2
        fi
        compute-random-sample \
            --input compute-constrained-features \
            --output "$query-sample" \
            --extension constrained.features \
            --size "$size" \
            --t-wise "$t_wise" \
            --seed "$query-2025-10-27"
    done

    # run non-winning SAT solvers using various queries
    solve \
        --kind sat \
        --query void \
        --input "$(mount-input),$(mount-sat-heritage)" \
        --timeout 1 \
        --attempts 1 \
        --solver_specs \
        "$(solve-sat-heritage yalsat-2017),solver,sat"
    solve_stages=("solve-void-sat")

    for query_spec in \
        "core;backbone;core" \
        "dead;backbone;dead" \
        "partial-1;partial;partial -,-" \
        "partial-2;partial;partial -,+" \
        "partial-3;partial;partial +,-" \
        "partial-4;partial;partial +,+"; do
        query_name=$(echo "$query_spec" | cut -d';' -f1)
        query_input=$(echo "$query_spec" | cut -d';' -f2)
        query_iterator=$(echo "$query_spec" | cut -d';' -f3)
        # shellcheck disable=SC2086
        solve \
            --kind sat \
            --query "$query_name" \
            --input "$(mount-input),$(mount-sat-heritage),$(mount-query-sample $query_input-sample)" \
            --timeout 1 \
            --attempts 1 \
            --query-iterator "$(to-lambda query-$query_iterator constrained.features)" \
            --solver_specs \
            "$(solve-sat-heritage yalsat-2017),solver,sat"
        solve_stages+=("solve-$query_name-sat")
    done

    aggregate --output solve-sat --inputs "${solve_stages[@]}"

    # solve \
    #     --kind sat \
    #     --input "$(mount-sat-heritage)" \
    #     --timeout "$SOLVE_TIMEOUT"  \
    #     --solver_specs \
    #     "$(solve-sat-heritage 2clseq-2002),solver,sat" \
    #     "$(solve-sat-heritage compsat-2005),solver,sat" \
    #     "$(solve-sat-heritage barcelogic-2007),solver,sat" \
    #     "$(solve-sat-heritage black_hole_sat-2011),solver,sat" \
    #     "$(solve-sat-heritage penelope-2014),solver,sat" \
    #     "$(solve-sat-heritage yalsat-2017),solver,sat" \
    #     "$(solve-sat-heritage parafrost-2020),solver,sat" \
    #     other/IsaSAT,solver,sat
}
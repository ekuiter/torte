#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# A secondary experiment that evaluates non-winning SAT competition solvers on the Linux kernel.
# We query randomly for core and dead features, as well as partial configurations.

SOLVE_TIMEOUT=120 # use same internal timeout as sbva_cadical in main evaluation

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

    transform-with-featjar \
        --transformer transform-to-smt-with-z3 \
        --output-extension smt \
        --jobs 8
    run \
        --image z3 \
        --input transform-to-smt-with-z3 \
        --output transform-to-dimacs \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 8
    join-into transform-to-smt-with-z3 transform-to-dimacs
    join-into extract-kconfig-models transform-to-dimacs

    # compute two samples: one for backbone (core/dead) queries, one for partial configuration queries
    compute-constrained-features
    for query in backbone partial; do
        if [[ $query == backbone ]]; then
            size=50
            t_wise=1
        elif [[ $query == partial ]]; then
            size=25
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
    
    # we use these solvers to corroborate our time-travel experiments on Linux Kconfig models
    # in our experiments, we focus on the winning SAT solvers from each year
    # however, we also want to investigate how non-winning SAT solvers perform (and evolve) on the kernel
    # most of these solvers were made available by the SAT heritage initiative
    # we manually exclude winning solvers, solvers related to winning solvers (i.e., I from the same family), and defunct solvers
    # we also screen solvers that are too slow or return wrong results

    # barcelogic participated in 2008, but we could not obtain binaries for that year, so we use the 2007 version
    # https://m-fleury.github.io/isasat/isasat-release/ Isabelle-verified SAT solver
    # https://www.cs.toronto.edu/~fbacchus/sat.html 2clseq solver
    # https://fmv.jku.at/compsat/
    # https://www.academia.edu/22542285/PeneLoPe_in_SAT_Competition_2014 parallel portfolio-based solver
    # https://fmv.jku.at/yalsat/ local search solver
    # https://github.com/muhos/ParaFROST parallel solver with GPU-accelerated inprocessing
    local solver_specs=(
        sat-museum/limmat-2002,solver,sat
        "$(solve-sat-heritage 2clseq-2002),solver,sat"
        "$(solve-sat-heritage unitwalk-2002),solver,sat"
        sat-museum/satelite-gti-2005.sh,solver,sat
        "$(solve-sat-heritage compsat-2005),solver,sat"
        "$(solve-sat-heritage haifasat-2005),solver,sat"
        sat-museum/minisat-2008,solver,sat
        "$(solve-sat-heritage barcelogic-2007),solver,sat"
        "$(solve-sat-heritage tinisat-2007),solver,sat"
        sat-museum/glucose-2011.sh,solver,sat
        "$(solve-sat-heritage black_hole_sat-2011),solver,sat"
        "$(solve-sat-heritage adaptg2wsat2011-2011),solver,sat"
        sat-museum/lingeling-2014,solver,sat
        "$(solve-sat-heritage penelope-2014),solver,sat"
        "$(solve-sat-heritage rokk-2014),solver,sat"
        sat-museum/maple-lcm-dist-2017,solver,sat
        "$(solve-sat-heritage yalsat-2017),solver,sat"
        "$(solve-sat-heritage candy-2017),solver,sat"
        sat-museum/kissat-2020,solver,sat
        "$(solve-sat-heritage parafrost-2020),solver,sat"
        "$(solve-sat-heritage pausat-2020),solver,sat"
        other/IsaSAT,solver,sat
        other/MergeSat,solver,sat
        # omit 2023 solver sbva_cadical to reduce runtime and because it has no museum counterpart
    )

    solve \
        --kind sat \
        --query void \
        --input "$(mount-dimacs-input),$(mount-sat-heritage)" \
        --timeout "$SOLVE_TIMEOUT"  \
        --solver_specs "${solver_specs[@]}"
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
            --input "$(mount-dimacs-input),$(mount-sat-heritage),$(mount-query-sample $query_input-sample)" \
            --timeout "$SOLVE_TIMEOUT"  \
            --query-iterator "$(to-lambda query-$query_iterator constrained.features)" \
            --solver_specs "${solver_specs[@]}"
        solve_stages+=("solve-$query_name-sat")
    done

    aggregate --output solve-sat --inputs "${solve_stages[@]}"
}
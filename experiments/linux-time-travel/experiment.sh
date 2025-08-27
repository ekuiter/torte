#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# This experiment extracts a yearly history of feature models from the Linux kernel and races it against the corresponding year's SAT solvers.
# On an Intel Xeon E5-2630 machine with 2.40GHz and 1TiB RAM, extraction and transformation takes under one day and SAT solving takes about three weeks.

SOLVE_TIMEOUT=1200 # timeout for SAT solvers in seconds (rarely needed)
ITERATIONS=5 # number of iterations for extraction and transformation
SOLVE_ITERATIONS=3 # number of iterations for SAT solving

if is-testing; then
    SOLVE_TIMEOUT=10
    ITERATIONS=2
    SOLVE_ITERATIONS=2
fi

experiment-systems() {
    add-linux-system
    # choose the last revision of Linux for each year from 2002-2024,
    # which can then be analyzed with the corresponding year's SAT competition solver
    add-linux-kconfig-revisions --revisions \
        "$(echo "v2.5.53 v2.6.0 v2.6.10 v2.6.14 v2.6.19 v2.6.23 v2.6.28" \
                "v2.6.32 v2.6.36 v3.1 v3.7 v3.12 v3.18 v4.3 v4.9 v4.14 v4.20" \
                "v5.4 v5.10 v5.15 v6.1 v6.6 v6.12" | tr ' ' '\n')" --architecture x86
    # extract second architecture for increased validity
    add-linux-kconfig-revisions --revisions \
        "$(echo "v2.5.53 v2.6.0 v2.6.10 v2.6.14 v2.6.19 v2.6.23 v2.6.28" \
                "v2.6.32 v2.6.36 v3.1 v3.7 v3.12 v3.18 v4.3 v4.9 v4.14 v4.20" \
                "v5.4 v5.10 v5.15 v6.1 v6.6 v6.12" | tr ' ' '\n')" --architecture arm
}

experiment-test-systems() {
    add-linux-system
    add-linux-kconfig-revisions --revisions v6.12 --architecture x86
}

experiment-stages() {
    clone-systems
    tag-linux-revisions
    read-statistics --option skip-sloc

    # extract (with two KConfig extractors)
    extract-kconfig-models \
        --iterations "$ITERATIONS" \
        --iteration-field extract-iteration \
        --file-fields model_file
    join-into read-statistics extract-kconfig-models

    # transform (with two CNF transformations)
    transform-model-with-featjar \
        --transformer transform-model-to-smt-with-z3 \
        --output-extension smt \
        --jobs 8
    # we don't iterate this CNF transformation because it is fully deterministic
    iterate \
        --iterations 1 \
        --iteration-field transform-iteration \
        --file-fields dimacs_file \
        --image z3 \
        --input transform-model-to-smt-with-z3 \
        --output transform-smt-to-dimacs-with-z3 \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 8
    join-into transform-model-to-smt-with-z3 transform-smt-to-dimacs-with-z3

    transform-model-with-featjar \
        --transformer transform-model-to-model-with-featureide \
        --output-extension featureide.model \
        --jobs 8
    iterate \
        --iterations "$ITERATIONS" \
        --iteration-field transform-iteration \
        --file-fields dimacs_file \
        --image kconfigreader \
        --input transform-model-to-model-with-featureide \
        --output transform-model-to-dimacs-with-kconfigreader \
        --command transform-model-to-dimacs-with-kconfigreader \
        --input-extension featureide.model \
        --jobs 8
    join-into transform-model-to-model-with-featureide transform-model-to-dimacs-with-kconfigreader
    
    aggregate \
        --output transform-model-to-dimacs \
        --directory-field dimacs_transformer \
        --file-fields dimacs_file \
        --inputs transform-model-to-dimacs-with-kconfigreader transform-smt-to-dimacs-with-z3
    join-into extract-kconfig-models transform-model-to-dimacs

    # analyze (not parallelized so as not to disturb time measurements)
    solve \
        --kind sat \
        --iterations "$SOLVE_ITERATIONS" \
        --timeout "$SOLVE_TIMEOUT" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs \
        sat-competition/02-zchaff,solver,sat \
        sat-competition/03-Forklift,solver,sat \
        sat-competition/04-zchaff,solver,sat \
        sat-competition/05-SatELiteGTI.sh,solver,sat \
        sat-competition/06-MiniSat,solver,sat \
        sat-competition/07-RSat.sh,solver,sat \
        sat-competition/08-MiniSat,solver,sat \
        sat-competition/09-precosat,solver,sat \
        sat-competition/10-CryptoMiniSat,solver,sat \
        sat-competition/11-glucose.sh,solver,sat \
        sat-competition/12-glucose.sh,solver,sat \
        sat-competition/13-lingeling-aqw,solver,sat \
        sat-competition/14-lingeling-ayv,solver,sat \
        sat-competition/15-abcdSAT,solver,sat \
        sat-competition/16-MapleCOMSPS_DRUP,solver,sat \
        sat-competition/17-Maple_LCM_Dist,solver,sat \
        sat-competition/18-MapleLCMDistChronoBT,solver,sat \
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat \
        sat-competition/20-Kissat-sc2020-sat,solver,sat \
        sat-competition/21-Kissat_MAB,solver,sat \
        sat-competition/22-kissat_MAB-HyWalk,solver,sat \
        sat-competition/23-sbva_cadical.sh,solver,sat \
        sat-competition/24-kissat-sc2024,solver,sat \
        other/SAT4J.210.sh,solver,sat \
        other/SAT4J.231.sh,solver,sat \
        other/SAT4J.235.sh,solver,sat \
        sat-museum/limmat-2002,solver,sat \
        sat-museum/berkmin-2003.sh,solver,sat \
        sat-museum/zchaff-2004,solver,sat \
        sat-museum/satelite-gti-2005.sh,solver,sat \
        sat-museum/minisat-2006,solver,sat \
        sat-museum/rsat-2007.sh,solver,sat \
        sat-museum/minisat-2008,solver,sat \
        sat-museum/precosat-2009,solver,sat \
        sat-museum/cryptominisat-2010,solver,sat \
        sat-museum/glucose-2011.sh,solver,sat \
        sat-museum/glucose-2012.sh,solver,sat \
        sat-museum/lingeling-2013,solver,sat \
        sat-museum/lingeling-2014,solver,sat \
        sat-museum/abcdsat-2015.sh,solver,sat \
        sat-museum/maple-comsps-drup-2016,solver,sat \
        sat-museum/maple-lcm-dist-2017,solver,sat \
        sat-museum/maple-lcm-dist-cb-2018,solver,sat \
        sat-museum/maple-lcm-disc-cb-dl-v3-2019,solver,sat \
        sat-museum/kissat-2020,solver,sat \
        sat-museum/kissat-mab-2021,solver,sat \
        sat-museum/kissat-mab-hywalk-2022,solver,sat
}
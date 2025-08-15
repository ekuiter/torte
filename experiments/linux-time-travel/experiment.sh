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
LINUX_CLONE_MODE=original # uncomment to include revisions >= v6.11 (requires case-insensitive file system)

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

experiment-stages() {
    clone-systems
    tag-linux-revisions
    read-statistics skip-sloc

    # extract (with two KConfig extractors)
    extract-kconfig-models \
        --iterations "$ITERATIONS" \
        --iteration-field extract-iteration \
        --file-fields model-file
    join-into read-statistics kconfig

    # transform (with two CNF transformations)
    transform-model-with-featjar \
        --transformer model_to_smt_z3 \
        --output-extension smt \
        --jobs 8
    # we don't iterate this CNF transformation because it is fully deterministic
    iterate \
        --iterations 1 \
        --iteration-field transform-iteration \
        --file-fields dimacs-file \
        --image z3 \
        --input model_to_smt_z3 \
        --output smt_to_dimacs_z3 \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 8
    join-into model_to_smt_z3 smt_to_dimacs_z3

    transform-model-with-featjar \
        --transformer model_to_model_featureide \
        --output-extension featureide.model \
        --jobs 8
    iterate \
        --iterations "$ITERATIONS" \
        --iteration-field transform-iteration \
        --file-fields dimacs-file \
        --image kconfigreader \
        --input model_to_model_featureide \
        --output model_to_dimacs_kconfigreader \
        --command transform-model-to-dimacs-with-kconfigreader \
        --input-extension featureide.model \
        --jobs 8
    join-into model_to_model_featureide model_to_dimacs_kconfigreader
    
    aggregate \
        --output dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --inputs model_to_dimacs_kconfigreader smt_to_dimacs_z3
    join-into kconfig dimacs

    # analyze (not parallelized so as not to disturb time measurements)
    solve \
        --kind model-satisfiable \
        --iterations "$SOLVE_ITERATIONS" \
        --timeout "$SOLVE_TIMEOUT" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs \
        sat-competition/02-zchaff,solver,satisfiable \
        sat-competition/03-Forklift,solver,satisfiable \
        sat-competition/04-zchaff,solver,satisfiable \
        sat-competition/05-SatELiteGTI.sh,solver,satisfiable \
        sat-competition/06-MiniSat,solver,satisfiable \
        sat-competition/07-RSat.sh,solver,satisfiable \
        sat-competition/08-MiniSat,solver,satisfiable \
        sat-competition/09-precosat,solver,satisfiable \
        sat-competition/10-CryptoMiniSat,solver,satisfiable \
        sat-competition/11-glucose.sh,solver,satisfiable \
        sat-competition/12-glucose.sh,solver,satisfiable \
        sat-competition/13-lingeling-aqw,solver,satisfiable \
        sat-competition/14-lingeling-ayv,solver,satisfiable \
        sat-competition/15-abcdSAT,solver,satisfiable \
        sat-competition/16-MapleCOMSPS_DRUP,solver,satisfiable \
        sat-competition/17-Maple_LCM_Dist,solver,satisfiable \
        sat-competition/18-MapleLCMDistChronoBT,solver,satisfiable \
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable \
        sat-competition/20-Kissat-sc2020-sat,solver,satisfiable \
        sat-competition/21-Kissat_MAB,solver,satisfiable \
        sat-competition/22-kissat_MAB-HyWalk,solver,satisfiable \
        sat-competition/23-sbva_cadical.sh,solver,satisfiable \
        sat-competition/24-kissat-sc2024,solver,satisfiable \
        other/SAT4J.210.sh,solver,satisfiable \
        other/SAT4J.231.sh,solver,satisfiable \
        other/SAT4J.235.sh,solver,satisfiable \
        sat-museum/limmat-2002,solver,satisfiable \
        sat-museum/berkmin-2003.sh,solver,satisfiable \
        sat-museum/zchaff-2004,solver,satisfiable \
        sat-museum/satelite-gti-2005.sh,solver,satisfiable \
        sat-museum/minisat-2006,solver,satisfiable \
        sat-museum/rsat-2007.sh,solver,satisfiable \
        sat-museum/minisat-2008,solver,satisfiable \
        sat-museum/precosat-2009,solver,satisfiable \
        sat-museum/cryptominisat-2010,solver,satisfiable \
        sat-museum/glucose-2011.sh,solver,satisfiable \
        sat-museum/glucose-2012.sh,solver,satisfiable \
        sat-museum/lingeling-2013,solver,satisfiable \
        sat-museum/lingeling-2014,solver,satisfiable \
        sat-museum/abcdsat-2015.sh,solver,satisfiable \
        sat-museum/maple-comsps-drup-2016,solver,satisfiable \
        sat-museum/maple-lcm-dist-2017,solver,satisfiable \
        sat-museum/maple-lcm-dist-cb-2018,solver,satisfiable \
        sat-museum/maple-lcm-disc-cb-dl-v3-2019,solver,satisfiable \
        sat-museum/kissat-2020,solver,satisfiable \
        sat-museum/kissat-mab-2021,solver,satisfiable \
        sat-museum/kissat-mab-hywalk-2022,solver,satisfiable
}
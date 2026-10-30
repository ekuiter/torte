#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment implements my reproducible PhD thesis.
# It leverages the multipass architecture so that it can be entirely executed in one experiment.
# This provides code reuse, full automation, and notably also reuse of cloned systems and
# extracted feature models, which saves a ton of disk space/time and manually shuffling around data.

# each experiment pass corresponds to one chapter of the PhD thesis
# you can also adjust this to execute experiments only for a single chapter (no changes below needed)
# however, executing _more than one_ chapter generally only works if 3a-extraction is included as well
PASSES=(3a-extraction 3b-transformation 4-configurability 5-scalability 6-differencing)

# these are all the systems we analyze (although not every pass analyzes every system)
# for reproducibility, we specify the latest release (for tags) and commit (for sampling) as of 2026-10-27
# for systems without tags, also include the latest extracted commit (needed by the transformation pass)
SYSTEMS_SPECS=(
    axtls,release-2.1.5,4bf767c8fdf907fb8d6ec7c877ac6a4023c2a35d
    barebox,v2026.10.0,26ba70a71b5303731699b5ac5be54ee3639641f8
    buildroot,2026.08,8fcca1794b352223f868daab062045860a827a45
    busybox,1_38_0,5eee8017a827659b6fb9e29ab1241eb4227c56f7
    coreboot,26.09,206078d6d990d0b7e51b5d87bc27349cb960ead0
    crosstool-ng,crosstool-ng-1.29.0,deacc28df92242014699eac9220e1d18fac3eeb6
    embtoolkit,embtoolkit-1.9.0,b9b2687bcb114f9b80381b9357aa3fe2d06e7d26
    entware,,36db8558ac7840d993cb11df1e47e0326d681077,a436d6db
    freetz-ng,,7f9bc7ec79c2b01c53839d1f6c4bda21304caa15,bf8d35c9b2
    l4re,,50bbe8a981199e17865e8553a4eb02c387b339cf,627ff6f5
    linux,v7.3,e0d4c87f25acfef9071baf9d1cb08d65084e0baa
    nuttx,nuttx-13.1.0,a31c15492e1d093b251d7ec8ad096255c4042df3
    openadk,,7fe21d0a9b1a129e86f218454b56c753a81831b5,e503a8429
    openwrt,v25.12.6,936801c4489b02ad39eadd1a9b26d38dd3a40e0f
    ptxdist,ptxdist-2026.10.0,25578c25031573977db826d12d05156574cc2898
    soletta,v2_rc2,5ca6d6a70bead00caf154b445755be94f3f68099
    tizenrt,v3.1_PRE,2d8977a265446a112f798fd9ca9de9c7f38ee1fa
    toybox,0.8.15,6a0c0ef5eeb2c43e4feef9781398c1718b8bddcb
    u-boot,v2026.10,04221f81e6b92681ed699d0fb380ef202e8a16fd
    uclibc-ng,v1.0.59,6246033750a5fc54e596e44656f710b6d8043e9a
    uclibc,v0.9.33.2,ca1c74d67dd115d059a875150e10b8560a9c35a8
    uclibcxx,,6687fc9276fa52defaf8592f2001c19b826aec93,7518644
    uclinux-dist,release/v2.1-p1,3943b15c6eb3842394d4f65db3eeabbba77f5529
    unikraft,RELEASE-0.21.0,359307a2a4cc9c1feb22683d841650902b799e4d
    xvisor,v0.3.2,ddbfcd6aee19ba3e2687f18f1d246744edad3495
)

# number of parallel jobs in miscellaneous stages, defaults to the available CPU cores
JOBS_MISC=$(cpu-cores)

# number of parallel jobs in heavy-to-compute stages, by default a quarter of the available cores, at least one
# we choose a conservative amount of course to avoid disturbing time measurements and reaching the memory limit
JOBS_HARD=$(( $(cpu-cores) / 4 ))
if (( JOBS_HARD < 1 )); then JOBS_HARD=1; fi

# if is-testing; then
#     SOLVE_TIMEOUT=10 # todo
# fi

# disable certain problematic combinations of system and extractor
add-restrictions-payload-file restrictions.csv

# register Jupyter notebooks for later execution (e.g., for plotting results)
# add-payload-file 3a-extraction.ipynb
# add-payload-file 3b-transformation.ipynb
# add-payload-file 4-configurability.ipynb
# ...

# define which systems are analyzed in each pass of the experiment
experiment-systems() {
    local system_spec system to branch latest_extracted
    if in-pass 3a-extraction; then
        # extract feature models for all analyzed systems
        for system_spec in "${SYSTEMS_SPECS[@]}"; do
            IFS=, read -r system to branch latest_extracted <<< "$system_spec"
            local options=()
            if [[ $system == linux ]]; then
                options=(--architecture all) # for linux, we want to extract all architectures (not just x86)
            fi
            if has-command add-"${system}"-kconfig-tags; then
                add-"${system}"-kconfig-tags --to "$to" "${options[@]}"
                add-"${system}"-kconfig-sample-last-tag-per-year --from 2002 --to 2026
            else
                add-"${system}"-kconfig-sample --branch "$branch" "${options[@]}"
            fi
        done
    elif in-pass 3b-transformation; then
        # use the latest pinned release, or the latest sampled revision that was extracted in the previous pass
        for system_spec in "${SYSTEMS_SPECS[@]}"; do
            IFS=, read -r system to branch latest_extracted <<< "$system_spec"
            add-"${system}"-kconfig --revision "${to:-${latest_extracted:-$branch}}"
        done
    elif in-pass 4-configurability; then
        # analyze all tagged revisions and architectures of the Linux kernel
        for system_spec in "${SYSTEMS_SPECS[@]}"; do
            IFS=, read -r system to branch latest_extracted <<< "$system_spec"
            if [[ $system == linux ]]; then
                add-linux-kconfig-tags --to "$to" --architecture all
            fi
        done
    elif in-pass 5-scalability; then
        # choose the last revision of Linux for each year from 2002-2024,
        # which can then be analyzed with the corresponding year's SAT competition solver
        add-linux-kconfig-revisions \
            --revisions "$(linux-tags \
                | git-last-revision-per-year --system linux --from 2002 --to 2024)"
    elif in-pass 6-differencing; then
        # analyze all tagged neighboring-revision pairs, if any, or use a yearly sample
        for system_spec in "${SYSTEMS_SPECS[@]}"; do
            IFS=, read -r system to branch latest_extracted <<< "$system_spec"
            if has-command add-"${system}"-kconfig-tags; then
                add-"${system}"-kconfig-tags --to "$to"
            else
                add-"${system}"-kconfig-sample --branch "$branch"
            fi
        done
    fi
}

experiment-test-systems(__NO_CI__) {
    : # todo
}

# define the stages of the experiment, which are executed in order for each pass
experiment-stages() {
    local extract_timeout=1200 # timeout for feature-model extraction in seconds

    if ! in-first-pass; then
        # we can reuse these stages in later passes for a considerable speedup
        reuse-stage-from-previous-pass --stage clone-systems
        reuse-stage-from-previous-pass --stage read-statistics
        reuse-stage-from-previous-pass --stage extract-kconfig-models --will-resume y
    fi

    # first, clone the repositories of all analyzed systems
    clone-systems

    # read statistics (i.e., committer dates and source lines of code)
    read-statistics

    # extract all feature models requested in experiment-systems()
    extract-kconfig-models \
        --with-kconfigreader y \
        --with-kclause y \
        --timeout "$extract_timeout" \
        --date-prefix "$(date-format time)"
    join-into read-statistics extract-kconfig-models

    # move on to the specific computations of each individual pass (implemented below)
    experiment-stages-"$PASS"

    # finally, execute the Jupyter notebook of the current pass to generate plots and tables
    # run-jupyter-notebook --payload-file "$PASS.ipynb"
    # run-jupyter-notebook \
    #     --input transform=transform-to-dimacs,sat=solve-sat,sharp=solve-sharp-sat \
    #     --payload-file evaluation.ipynb
    # run-jupyter-notebook \
    #     --input read-linux-architectures=read-linux-architectures,read-linux-configs=read-linux-configs,kconfig=extract-kconfig-models,model_to_uvl_featureide=transform-to-uvl,model_to_smt_z3=transform-to-dimacs,dimacs=transform-to-dimacs,backbone-dimacs=transform-dimacs-to-backbone-dimacs,solve_model-count=solve-sharp-sat,compute-linux-feature-statistics=compute-linux-feature-statistics \
    #     --payload-file evaluation.ipynb
    # run-jupyter-notebook \
    #     --input dimacs=transform-to-dimacs,solve_model-satisfiable=solve-sat \
    #     --payload-file evaluation.ipynb
}

experiment-stages-3a-extraction() {
    : # this pass has no specific computations
}

experiment-stages-3b-transformation() {
    local transform_iterations=3 # number of iterations for CNF transformation
    local transform_timeout=180 # timeout for CNF transformation in seconds
    local solve_timeout=1200 # timeout for model counting in seconds
    local sample_num_features=3 # number of randomly sampled feature queries
    local sample_seed=20261026 # fixed seed for reproducible random samples

    local sat_solver_specs=(
        sat-competition/02-zchaff,solver,sat
        sat-competition/03-Forklift,solver,sat
        sat-competition/04-zchaff,solver,sat
        sat-competition/05-SatELiteGTI.sh,solver,sat
        sat-competition/06-MiniSat,solver,sat
        sat-competition/07-RSat.sh,solver,sat
        sat-competition/09-precosat,solver,sat
        sat-competition/10-CryptoMiniSat,solver,sat
        sat-competition/11-glucose.sh,solver,sat
        sat-competition/12-glucose.sh,solver,sat
        sat-competition/13-lingeling-aqw,solver,sat
        sat-competition/14-lingeling-ayv,solver,sat
        sat-competition/16-MapleCOMSPS_DRUP,solver,sat
        sat-competition/17-Maple_LCM_Dist,solver,sat
        sat-competition/18-MapleLCMDistChronoBT,solver,sat
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat
        sat-competition/20-Kissat-sc2020-sat,solver,sat
        sat-competition/21-Kissat_MAB,solver,sat
    )

    local sharp_sat_solver_specs=(
        emse-2023/countAntom,solver,sharp-sat
        emse-2023/d4,solver,sharp-sat
        emse-2023/dSharp,solver,sharp-sat
        emse-2023/ganak,solver,sharp-sat
        emse-2023/sharpSAT,solver,sharp-sat
    )

    # transform extracted feature models into CNF
    transform-to-dimacs \
        --with-featureide "$transform_iterations" \
        --with-kconfigreader "$transform_iterations" \
        --with-z3 "$transform_iterations" \
        --timeout "$transform_timeout" \
        --jobs "$JOBS_HARD"
    join-into extract-kconfig-models transform-to-dimacs

    # prepare feature samples for later solving
    compute-constrained-features --jobs "$JOBS_MISC"
    filter-dimacs-features \
        --input compute-constrained-features \
        --extension constrained.features \
        --jobs "$JOBS_MISC"
    compute-random-sample \
        --input filter-dimacs-features \
        --output feature-sample \
        --extension constrained.features \
        --size "$sample_num_features" \
        --seed "$sample_seed" \
        --jobs "$JOBS_MISC"

    # solve various SAT and #SAT queries on the transformed CNF formulas
    local kind query_spec query_name query_iterator
    local query_specs solver_specs solve_args solve_stages
    for kind in sat sharp-sat; do
        if [[ $kind == sat ]]; then
            query_specs=("void;" "core;core" "dead;dead")
            solver_specs=("${sat_solver_specs[@]}")
        else
            query_specs=("feature-model-cardinality;" "feature-cardinality;dead")
            solver_specs=("${sharp_sat_solver_specs[@]}")
        fi
        solve_stages=()
        for query_spec in "${query_specs[@]}"; do
            query_name=${query_spec%%;*}
            query_iterator=${query_spec#*;}
            solve_args=(
                --kind "$kind"
                --query "$query_name"
                --timeout "$solve_timeout"
                --jobs "$JOBS_HARD"
            )
            if [[ -n $query_iterator ]]; then
                solve_args+=(
                    --input "$(mount-dimacs-input),$(mount-query-sample feature-sample)"
                    --query-iterator "$(to-lambda "query-$query_iterator" constrained.features)"
                )
            fi
            solve "${solve_args[@]}" --solver_specs "${solver_specs[@]}"
            solve_stages+=("solve-$query_name-$kind")
        done
        aggregate --output "solve-$kind" --inputs "${solve_stages[@]}"
    done
}

experiment-stages-4-configurability() {
    local solve_timeout=3600 # timeout for model counting in seconds
    local solve_attempts=4 # how many successive timeouts are allowed before giving up and moving on

    local sharp_sat_solver_specs=(
        mcc-2022/d4.sh,solver,sharp-sat-mcc22
        mcc-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,sharp-sat-mcc22
    )

    # read additional Linux information for later analysis
    read-linux-names
    read-linux-architectures
    read-linux-configs
    join-into read-statistics read-linux-names
    join-into read-statistics read-linux-architectures
    compute-unconstrained-features --jobs "$JOBS_MISC"

    # transform extracted feature models into CNF
    transform-to-dimacs --with-z3 y --jobs "$JOBS_MISC"
    join-into extract-kconfig-models transform-to-dimacs

    # compute backbone (for counting the number of features)
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --jobs "$JOBS_HARD"
    join-into transform-to-dimacs transform-dimacs-to-backbone-dimacs
    compute-backbone-features --jobs "$JOBS_MISC"
    compute-linux-feature-statistics

    # solve #SAT (for counting the number of configurations)
    solve \
        --input transform-dimacs-to-backbone-dimacs \
        --input-extension backbone.dimacs \
        --kind sharp-sat \
        --timeout "$solve_timeout" \
        --jobs "$JOBS_HARD" \
        --attempts "$solve_attempts" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs "${sharp_sat_solver_specs[@]}"
    join-into transform-dimacs-to-backbone-dimacs solve-sharp-sat
}

experiment-stages-5-scalability() {
    local solve_timeout=1200 # timeout for SAT solvers in seconds (rarely needed)
    local iterations=5 # number of iterations for extraction and transformation
    local solve_iterations=3 # number of iterations for SAT solving

    local solver_specs=(
        sat-competition/02-zchaff,solver,sat
        sat-competition/03-Forklift,solver,sat
        sat-competition/04-zchaff,solver,sat
        sat-competition/05-SatELiteGTI.sh,solver,sat
        sat-competition/06-MiniSat,solver,sat
        sat-competition/07-RSat.sh,solver,sat
        sat-competition/08-MiniSat,solver,sat
        sat-competition/09-precosat,solver,sat
        sat-competition/10-CryptoMiniSat,solver,sat
        sat-competition/11-glucose.sh,solver,sat
        sat-competition/12-glucose.sh,solver,sat
        sat-competition/13-lingeling-aqw,solver,sat
        sat-competition/14-lingeling-ayv,solver,sat
        sat-competition/15-abcdSAT,solver,sat
        sat-competition/16-MapleCOMSPS_DRUP,solver,sat
        sat-competition/17-Maple_LCM_Dist,solver,sat
        sat-competition/18-MapleLCMDistChronoBT,solver,sat
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat
        sat-competition/20-Kissat-sc2020-sat,solver,sat
        sat-competition/21-Kissat_MAB,solver,sat
        sat-competition/22-kissat_MAB-HyWalk,solver,sat
        sat-competition/23-sbva_cadical.sh,solver,sat
        sat-competition/24-kissat-sc2024,solver,sat
        other/SAT4J.210.sh,solver,sat
        other/SAT4J.231.sh,solver,sat
        other/SAT4J.235.sh,solver,sat
    )

    # transform extracted feature models into CNF
    # we don't iterate Z3 because it is fully deterministic
    transform-to-dimacs \
        --with-kconfigreader "$iterations" \
        --with-z3 y \
        --jobs "$JOBS_HARD"
    join-into extract-kconfig-models transform-to-dimacs

    # solve SAT
    solve \
        --kind sat \
        --iterations "$solve_iterations" \
        --timeout "$solve_timeout" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs "${solver_specs[@]}"
}

experiment-stages-6-differencing() {
    local diff_iterations=3
    local diff_timeout=300
    local diff_attempts=3

    # prepare for differencing by computing pairs of non-duplicate versions to difference
    remove-duplicate-files --file-field model_file
    compute-file-pairs --file-field model_file --group-field system

    # compute differences between feature models using clausy
    # (see details on the evaluation runs in src/docker/clausy/scripts/evaluate_diff.sh)
    diff-with-clausy \
        --file-field model_file \
        --iterations "$diff_iterations" \
        --timeout "$diff_timeout" \
        --attempts "$diff_attempts" \
        --group-field system
}

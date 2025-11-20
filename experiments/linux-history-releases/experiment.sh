#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This file reproduces the evaluation for the TOSEM'25 paper "How Configurable is the Linux Kernel? Analyzing Two Decades of Feature-Model History".

# This experiment analyzes the feature model of the Linux kernel across a timespan of > 20 years
# and across all its supported processor architectures. For each revision and architecture, a
# feature model is extracted with both kconfigreader and kclause and then transformed into various
# file formats using FeatureIDE (XML, UVL) and Z3 (DIMACS). Then, each feature model's core and dead
# features and its model count are computed, if possible.
# Note that this experiment is time- and space-intensive: The extraction phase alone takes about
# one week and 170GiB free disk space to run. While re-running the entire experiment is possible,
# it is probably not needed, depending on your use case (e.g., only analyzing the latest revision).
# For an unattended run of the full evaluation, we recommend to use a machine with 1TiB of RAM and
# a 500GiB tmpfs ramdisk (it also works on consumer laptops, but takes ages without parallel jobs).
# Parallelization (i.e., JOBS > 1) massively speeds up the process, but as jobs can steal each other's
# memory, failures will occur more often. This does not affect most tasks, so we only reduce
# parallelization for model counting, which takes a lot of RAM.
# With at least 1TiB RAM, it is also possible to use a temporary file system for input and output:
# for d in input output; do mkdir -p $d; sudo mount -t tmpfs none $d; done

# parameters for computing model count
SOLVE_TIMEOUT=3600 # timeout in seconds
SOLVE_JOBS=4 # number of parallel jobs to run, should not exceed number of attempts
SOLVE_ATTEMPTS=4 # how many successive timeouts are allowed before giving up and moving on

if is-testing; then
    SOLVE_TIMEOUT=10
fi

add-payload-file evaluation.ipynb

experiment-systems() {
    # analyze all revisions and architectures of the Linux kernel
    add-linux-kconfig-history --from v2.5.45 --to v6.12 --architecture all
}

experiment-test-systems(__NO_CI__) {
    add-linux-kconfig-history --from v6.11 --to v6.12 --architecture x86
}

experiment-stages() {
    # extract
    clone-systems
    tag-linux-revisions
    read-linux-names
    read-linux-architectures
    read-linux-configs
    read-statistics
    join-into read-statistics read-linux-names
    join-into read-statistics read-linux-architectures
    extract-kconfig-models
    join-into read-statistics extract-kconfig-models
    compute-unconstrained-features --jobs 16

    # transform
    transform-to-uvl --jobs 16
    transform-to-dimacs --with-z3 y --jobs 16
    join-into extract-kconfig-models transform-to-dimacs

    # solve
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --jobs 16
    join-into transform-to-dimacs transform-dimacs-to-backbone-dimacs
    compute-backbone-features --jobs 16
    solve \
        --input transform-dimacs-to-backbone-dimacs \
        --input-extension backbone.dimacs \
        --kind sharp-sat \
        --timeout "$SOLVE_TIMEOUT" \
        --jobs "$SOLVE_JOBS" \
        --attempts "$SOLVE_ATTEMPTS" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs \
        mcc-2022/d4.sh,solver,sharp-sat-mcc22 \
        mcc-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,sharp-sat-mcc22
    join-into transform-dimacs-to-backbone-dimacs solve-sharp-sat

    # todo: evaluate
    # run-jupyter-notebook --payload-file evaluation.ipynb
}

# additional useful statistics on the mainline kernel, takes a while to run
git-statistics() {
    git -C input/linux checkout master
    echo -n "Number of all commits: "
    git -C input/linux rev-list HEAD --count
    echo -n "Number of tagged revisions: "
    git -C input/linux tag | start-at-revision v2.6.12 | wc -l
    echo -n "Number of releases: "
    linux-tag-revisions | start-at-revision v2.6.12 | wc -l
    echo -n "Number of all commits that touch Kconfig files: "
    git -C input/linux log --pretty=oneline --diff-filter=AMD --branches --tags -- '**/*Kconfig*' | wc -l
}

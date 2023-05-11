#!/bin/bash
# this code remains to be properly integrated

run-void-analysis() (
    cat $dimacs_path | grep -E "^[^c]" > input.dimacs
    echo "  Void feature model / feature model cardinality"
    suffix=""
    run-solver
)

run-core-dead-analysis() (
    features=$(cat $(echo $base | sed 's/kconfigreader/kclause/').features)
    i=1
    for f in $features; do
        fnum=$(cat $dimacs_path | grep " $f$" | cut -d' ' -f2 | head -n1)
        cat $dimacs_path | grep -E "^[^c]" > input.dimacs
        clauses=$(cat input.dimacs | grep -E ^p | cut -d' ' -f4)
        clauses=$((clauses + 1))
        sed -i "s/^\(p cnf [[:digit:]]\+ \)[[:digit:]]\+/\1$clauses/" input.dimacs
        echo "$2$fnum 0" >> input.dimacs
        echo "  $1 $f"
        suffix="$i-$f"
        run-solver
        i=$(($i+1))
    done
)

run-dead-analysis() (
    run-core-dead-analysis "Dead feature / feature cardinality" ""
)

run-core-analysis() (
    run-core-dead-analysis "Core feature" "-"
)

for dimacs_path in $(ls output/dimacs/*kclause*.dimacs | sort -V); do
    dimacs=$(basename $dimacs_path .dimacs)
    base_it=$(echo $dimacs_path | rev | cut -d, -f2- | rev)
    base=$(echo $base_it | sed 's/\(,.*,\).*,/\1/g')
    echo "Reading features for $dimacs"
    if [ ! -f $base.features ]; then
        touch $base.features
        features=$(cat $base_it,z3.dimacs | grep -E "^c [1-9]" | grep -v 'k!' | cut -d' ' -f3 | shuf --random-source=<(yes $RANDOM_SEED))
        i=1
        found=0
        while [ $found -lt $NUM_FEATURES ] && [ $i -le $(echo "$features" | wc -l) ]; do
            feature=$(echo "$features" | tail -n+$i | head -1)
            if ([ ! -f $base_it,featureide.dimacs ] || (cat $base_it,featureide.dimacs | grep -q " $feature$")) &&
               ([ ! -f $base_it,kconfigreader.dimacs ] || (cat $base_it,kconfigreader.dimacs | grep -q " $feature$")) &&
               ([ ! -f $base_it,z3.dimacs ] || (cat $base_it,z3.dimacs | grep -q " $feature$")); then
                echo $feature >> $base.features
                found=$(($found+1))
            else
                echo "WARNING: Feature $feature not found in all DIMACS files for $base_it" | tee -a $err
            fi
            i=$(($i+1))
        done
    fi
done

for dimacs_path in $(ls output/dimacs/*kclause*.dimacs | sort -V); do
    dimacs=$(basename $dimacs_path .dimacs)
    base=$(echo $dimacs_path | rev | cut -d, -f2- | rev | sed 's/\(,.*,\).*,/\1/g')
    echo "Solving $dimacs"
    for solver in $SOLVERS; do
        for analysis in $ANALYSES; do
            if [[ $solver != sharpsat-* ]] || [[ $analysis != core ]]; then
                run-$analysis-analysis
            fi
        done
    done
done
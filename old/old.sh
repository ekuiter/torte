#!/bin/bash
# stage 2c: collect statistics in CSV file
res=output/results_transform.csv
err=output/error_transform.log
res_miss=output/results_missing.csv

if [ ! -f $res ]; then
    echo system,tag,time,date,sloc,iteration,source,extract_time,extract_variables,extract_literals,transformation,transform_time,transform_variables,transform_literals >> $res

    for system_tag in $(cat $results_stats | cut -d, -f1-2 | tail -n+2); do
        i=0
        while [ $i -ne $N ]; do
            # todo: re-add check for missing models
            # system_tag=$(echo $system | tr , _)
            # model_num=$(ls output/models/$system* 2>/dev/null | wc -l)
            # if ! ([ $model_num -eq $(( 2*$N )) ] || ([ $model_num -eq $N ] && (ls output/models/$system* | grep -q hierarchy))); then
            #     echo "WARNING: Missing feature models for $system" | tee -a $err
            # else
            i=$(($i+1))
            for source in kconfigreader kclause hierarchy; do
                # if ! [ -f output/models/$system_tag,$i,$source.model ]; then
                #     stats=output/intermediate/$system_tag,$i,hierarchy.stats
                #     extract_time=NA
                #     extract_variables=$(cat $stats | cut -d' ' -f1)
                #     extract_literals=$(cat $stats | cut -d' ' -f2)
                # fi
                for transformation in featureide z3 kconfigreader; do
                    if ! [ -f output/dimacs/$system_tag,$i,$source,$transformation* ]; then
                        echo "WARNING: Missing DIMACS file for $system_tag with source $source and transformation $transformation" | tee -a $err
                        echo $system_tag,$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,NA,NA,NA >> $res
                        for solver in ${SOLVERS[@]}; do
                            for analysis in ${ANALYSES[@]}; do
                                if [[ $solver != sharpsat-* ]] || [[ $analysis != core ]]; then
                                    if [[ $analysis == void ]]; then
                                        echo $system_tag,$i,$source,$transformation,$solver,$analysis,NA,NA,NA >> $res_miss
                                    else
                                        j=0
                                        while [ $j -ne $NUM_FEATURES ]; do
                                            j=$(($j+1))
                                            echo $system_tag,$i,$source,$transformation,$solver,$analysis$j,NA,NA,NA >> $res_miss
                                        done
                                    fi
                                fi
                            done
                        done
                    fi
                done
            done
        done
    done
else
    echo Skipping stage 2c
fi

# stage 3: analyze transformed feature models with (#)SAT solvers
res=output/results_analyze.csv
err=output/error_analyze.log
if [ ! -f $res ] && [[ $SKIP_ANALYSIS != y ]]; then
    rm -rf output/stage3_output $res $err
    mkdir -p output/stage3_output
    cp -r output/dimacs output/stage3_output/dimacs
    if [[ $SKIP_BUILD != y ]]; then
        docker build -f stage3/Dockerfile -t stage3 stage3
    fi
    docker run --rm -m $MEMORY_LIMIT -e ANALYSES -e TIMEOUT_ANALYZE -e RANDOM_SEED -e NUM_FEATURES -e SOLVERS -v $PWD/output/stage3_output:/home/output stage3 ./solve.sh
    cp output/stage3_output/results_analyze.csv $res
    cp output/stage3_output/error_analyze.log $err
    cat $res_miss >> $res
else
    echo Skipping stage 3
fi

echo
cat output/error*

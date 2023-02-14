#!/bin/bash
set -ea
shopt -s extglob # needed for @(...|...) syntax below

if [[ ! -f input/params.ini ]]; then
    echo "Evaluation parameters missing!"
    exit 1
fi

if [[ ! -f input/extract.sh ]]; then
    echo "Extraction script missing!"
    exit 1
fi

mkdir -p output

# clone repositories
chmod +x input/extract.sh
chmod +x input/prepare_linux_repository.sh
source input/params.ini
source input/extract.sh
source input/prepare_linux_repository.sh

# stage 0: get version dates and SLOCs
# todo: make this stage skippable (or at least cloc)
results_stats=output/results_stats.csv
if [ ! -f $results_stats ]; then
    if [[ $SKIP_BUILD != y ]]; then
        docker build -f stage0/Dockerfile -t stage0 stage0
    fi
    echo version,time,date,sloc | tee -a $results_stats
    docker run --rm -v $PWD/input:/home/input stage0 ./input/extract.sh | tee -a $results_stats
else
    echo Skipping stage 0
fi

# stage 1: extract feature models as .model files with kconfigreader-extract and kclause
if [[ ! -d output/models ]]; then
    # clean up previous (incomplete) files
    rm -rf output/kconfigreader output/kclause
    mkdir -p output/models

    # extract feature models with kconfigreader and kclause
    for reader in ${READERS[@]}; do
        # build Docker image
        if [[ $SKIP_BUILD != y ]]; then
            docker build -f stage1/$reader/Dockerfile -t stage1_$reader stage1
        fi

        # run evaluation script inside Docker container
        # for other evaluations, you can run other scripts (e.g., extract_all.sh)
        docker run --rm -m $MEMORY_LIMIT -e N -v $PWD/output/stage1_${reader}_output:/home/output -v $PWD/input:/home/input stage1_$reader ./input/extract.sh
        
        # arrange files for further processing
        for system in output/stage1_${reader}_output/models/*; do
            system=$(basename $system)
            for file in output/stage1_${reader}_output/models/$system/*.model; do
                cp output/stage1_${reader}_output/models/$system/$(basename $file) output/models/$system,$(basename $file)
            done
        done
    done

    # add hierarchical models from Knüppel's "Is there a mismatch" paper
    rm -f output/models/*.xml
    i=0
    while [ $i -ne $N ]; do
        i=$(($i+1))
        for h in ${HIERARCHIES[@]}; do
            cp input/hierarchies/$h.xml output/models/$(basename $h .xml),$i,hierarchy.xml
        done
    done
else
    echo Skipping stage 1
fi

# stage 2a: transform .model files into .dimacs (FeatureIDE), .smt (z3), and .model (kconfigreader-transform)
if [[ ! -d output/intermediate ]] || [[ ! -d output/dimacs ]]; then
    rm -rf output/stage2_output
    mkdir -p output/stage2_output output/intermediate output/dimacs
    ls output/models > output/stage2_output/models.txt
    cp -r output/models output/stage2_output/models

    # build and run Docker image (analogous to above)
    if [[ $SKIP_BUILD != y ]]; then
        docker build -f stage2/Dockerfile -t stage2 stage2
    fi
    docker run --rm -m $MEMORY_LIMIT -e TIMEOUT_TRANSFORM -v $PWD/output/stage2_output:/home/spldev/evaluation-cnf/output stage2 evaluation-cnf/transform.sh

    # arrange files for further processing
    for file in output/stage2_output/*/temp/*.@(dimacs|smt|model|stats); do
        newfile=$(basename $file | sed 's/\.model_/,/g' | sed 's/_0\././g' | sed 's/hierarchy_/hierarchy,/g')
        if [[ $newfile != *.stats ]] || [[ $newfile == *hierarchy* ]]; then
            cp $file output/intermediate/$newfile
        fi
    done
    mv output/intermediate/*.dimacs output/dimacs || true
else
    echo Skipping stage 2a
fi

# stage 2b: transform .smt and .model files into .dimacs with z3 and kconfigreader-transform
if ! ls output/dimacs | grep -q z3; then
    for reader in ${READERS[@]}; do
        rm -rf output/stage2_${reader}_output
        mkdir -p output/stage2_${reader}_output
        cp output/intermediate/*.@(smt|model) output/stage2_${reader}_output
        if [[ $SKIP_BUILD != y ]]; then
            docker build -f stage1/$reader/Dockerfile -t stage1_$reader stage1
        fi
        docker run --rm -m $MEMORY_LIMIT -e TIMEOUT_TRANSFORM -v $PWD/output/stage2_${reader}_output:/home/output stage1_$reader ./transform.sh
        cp output/stage2_${reader}_output/*.dimacs output/dimacs || true
    done
else
    echo Skipping stage 2b
fi

# stage 2c: collect statistics in CSV file
res=output/results_transform.csv
err=output/error_transform.log
res_miss=output/results_missing.csv

if [ ! -f $res ]; then
    rm -f $res $err $res_miss
    echo system,tag,time,date,sloc,iteration,source,extract_time,extract_variables,extract_literals,transformation,transform_time,transform_variables,transform_literals >> $res
    touch $err $res_miss

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
                if [ -f output/models/$system_tag,$i,$source* ]; then
                    model=output/models/$system_tag,$i,$source.model
                    stats=output/intermediate/$system_tag,$i,hierarchy.stats
                    echo "Processing $model"
                    if [ -f $model ]; then
                        extract_time=$(cat $model | grep "#item time" | cut -d' ' -f3)
                        extract_variables=$(cat $model | sed "s/)/)\n/g" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
                        extract_literals=$(cat $model | sed "s/)/)\n/g" | grep "def(" | wc -l)
                    else
                        extract_time=NA
                        extract_variables=$(cat $stats | cut -d' ' -f1)
                        extract_literals=$(cat $stats | cut -d' ' -f2)
                    fi
                    for transformation in z3 kconfigreader; do ## todo: featureide
                        if ([[ $source == kconfigreader ]] && [[ $transformation == kconfigreader ]]) ||
                            ([[ $source == kclause ]] && [[ $transformation == z3 ]]) ; then
                            if [ -f output/dimacs/$system_tag,$i,$source,$transformation* ]; then
                                dimacs=output/dimacs/$system_tag,$i,$source,$transformation.dimacs
                                echo Processing $dimacs
                                transform_time=$(cat $dimacs | grep "c time" | cut -d' ' -f3)
                                transform_variables=$(cat $dimacs | grep -E ^p | cut -d' ' -f3)
                                transform_literals=$(cat $dimacs | grep -E "^[^pc]" | grep -Fo ' ' | wc -l)
                                echo $system_tag,$(cat $results_stats | grep $system_tag | cut -d, -f3-),$i,$source,$extract_time,$extract_variables,$extract_literals,$transformation,$transform_time,$transform_variables,$transform_literals >> $res
                            else
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
                        fi
                    done
                fi
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

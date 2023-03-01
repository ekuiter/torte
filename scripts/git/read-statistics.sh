#!/bin/bash
# ./read-statistics.sh [skip-sloc]
# counts number of source lines of codes using cloc

add-revision() (
    local system=$1
    local revision=$2
    require-value system revision
    echo "Reading statistics for $system $revision"
    local time=$(git -C $(input-directory)/$system --no-pager log -1 -s --format=%ct $revision)
    local date=$(date -d @$time +"%Y-%m-%d")
    echo $system,$revision,$time,$date >> $docker_output_directory/date.csv
    if [[ $option != skip-sloc ]]; then
        (cd input/$system; cloc --git $revision > $docker_output_directory/$revision.txt)
        local sloc=$(cat $docker_output_directory/$revision.txt | grep ^SUM | tr -s ' ' | cut -d' ' -f5)
        echo $system,$revision,$sloc >> $docker_output_directory/sloc.csv
    else
        echo $system,$revision,NA >> $docker_output_directory/sloc.csv
    fi
)

option=$1
source main.sh init
echo system,revision,time,date > $docker_output_directory/date.csv
echo system,revision,sloc > $docker_output_directory/sloc.csv
source main.sh load
join-tables $docker_output_directory/date.csv $docker_output_directory/sloc.csv 2 > $(output-csv)
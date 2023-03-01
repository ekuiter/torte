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
    echo $system,$revision,$time,$date >> $(output-directory)/date.csv
    if [[ $option != skip-sloc ]]; then
        (cd input/$system; cloc --git $revision > $(output-directory)/$revision.txt)
        local sloc=$(cat $(output-directory)/$revision.txt | grep ^SUM | tr -s ' ' | cut -d' ' -f5)
        echo $system,$revision,$sloc >> $(output-directory)/sloc.csv
    else
        echo $system,$revision,NA >> $(output-directory)/sloc.csv
    fi
)

option=$1
source main.sh load-config
echo system,revision,time,date > $(output-directory)/date.csv
echo system,revision,sloc > $(output-directory)/sloc.csv
source main.sh load-subjects
join-tables $(output-directory)/date.csv $(output-directory)/sloc.csv 2 > $(output-csv)
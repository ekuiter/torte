#!/bin/bash
# ./read-statistics.sh [skip-sloc]
# counts number of source lines of codes using cloc

SCRIPT_OPTION=$1

add-revision() {
    local system=$1
    local revision=$2
    require-value system revision
    echo "Reading statistics for $system $revision"
    local time
    time=$(git -C "$(input-directory)/$system" --no-pager log -1 -s --format=%ct "$revision")
    local date
    date=$(date -d "@$time" +"%Y-%m-%d")
    echo "$system,$revision,$time,$date" >> "$(output-directory)/date.csv"
    if [[ $SCRIPT_OPTION != skip-sloc ]]; then
        (cd "input/$system"; cloc --git "$revision" > "$(output-directory)/$revision.txt")
        local sloc
        sloc=$(grep ^SUM < "$(output-directory)/$revision.txt" | tr -s ' ' | cut -d' ' -f5)
        echo "$system,$revision,$sloc" >> "$(output-directory)/sloc.csv"
    else
        echo "$system,$revision,NA" >> "$(output-directory)/sloc.csv"
    fi
}

# shellcheck source=../../scripts/main.sh
source main.sh load-config
echo system,revision,time,date > "$(output-directory)/date.csv"
echo system,revision,sloc > "$(output-directory)/sloc.csv"
load-subjects
join-tables "$(output-directory)/date.csv" "$(output-directory)/sloc.csv" 2 > "$(output-csv)"
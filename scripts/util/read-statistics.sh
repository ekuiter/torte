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
        local sloc_file="$(output-directory)/$system/$revision.txt"
        mkdir -p "$(output-directory)/$system"
        (cd "input/$system"; cloc --git "$revision" > "$sloc_file")
        local sloc
        sloc=$(grep ^SUM < "$sloc_file" | tr -s ' ' | cut -d' ' -f5)
        echo "$system,$revision,$sloc" >> "$(output-directory)/sloc.csv"
    else
        echo "$system,$revision,NA" >> "$(output-directory)/sloc.csv"
    fi
}

# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
echo system,revision,committer_date_unix,committer_date_readable > "$(output-directory)/date.csv"
echo system,revision,source_lines_of_code > "$(output-directory)/sloc.csv"
load-subjects
join-tables "$(output-directory)/date.csv" "$(output-directory)/sloc.csv" > "$(output-csv)"
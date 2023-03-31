#!/bin/bash
# ./read-statistics.sh [skip-sloc]
# counts number of source lines of codes using cloc

load-config
SCRIPT_OPTION=$2

add-revision(system, revision) {
    local subject="read-statistics: $system@$revision"
    log "$subject" "$(echo-progress read)"
    local time
    time=$(git -C "$(input-directory)/$system" --no-pager log -1 -s --format=%ct "$revision")
    local date
    date=$(date -d "@$time" +"%Y-%m-%d")
    echo "$system,$revision,$time,$date" >> "$(output-directory)/date.csv"
    if [[ $SCRIPT_OPTION != skip-sloc ]]; then
        local sloc_file
        sloc_file="$(output-directory)/$system/$revision.txt"
        mkdir -p "$(output-directory)/$system"
        push "input/$system"
        cloc --git "$revision" > "$sloc_file"
        pop
        local sloc
        sloc=$(grep ^SUM < "$sloc_file" | tr -s ' ' | cut -d' ' -f5)
        echo "$system,$revision,$sloc" >> "$(output-directory)/sloc.csv"
    else
        echo "$system,$revision,NA" >> "$(output-directory)/sloc.csv"
    fi
    log "$subject" "$(echo-done)"
}

echo system,revision,committer_date_unix,committer_date_readable > "$(output-directory)/date.csv"
echo system,revision,source_lines_of_code > "$(output-directory)/sloc.csv"
load-subjects
join-tables "$(output-directory)/date.csv" "$(output-directory)/sloc.csv" > "$(output-csv)"
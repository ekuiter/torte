#!/bin/bash
# functions for working with Git repositories and statistics

# clones system repositories using git
clone-systems() {
    add-system(system, url) {
        log "git-clone: $system"
        if [[ ! -d "$(input-directory)/$system" ]]; then
            log "" "$(echo-progress clone)"
            git clone "$url" "$(input-directory)/$system"
            compile-hook post-clone-hook
            post-clone-hook "$system" "$url"
            log "" "$(echo-done)"
        else
            log "" "$(echo-skip)"
        fi
    }

    experiment-systems
}

# counts number of source lines of codes using cloc
read-statistics(statistics_option=) {
    STATISTICS_OPTION=$statistics_option

    add-revision(system, revision) {
        revision=$(clean-revision "$revision")
        log "read-statistics: $system@$revision" "$(echo-progress read)"
        if grep -q "^$system,$revision," "$(output-path date.csv)"; then
            log "" "$(echo-skip)"
            return
        fi
        local time
        time=$(git -C "$(input-directory)/$system" --no-pager log -1 -s --format=%ct "$revision")
        local date
        date=$(date -d "@$time" +"%Y-%m-%d")
        echo "$system,$revision,$time,$date" >> "$(output-path date.csv)"
        if [[ $STATISTICS_OPTION != skip-sloc ]]; then
            local sloc_file
            sloc_file=$(output-path "$system" "$revision.txt")
            push "input/$system"
            cloc --git "$revision" > "$sloc_file"
            pop
            local sloc
            sloc=$(grep ^SUM < "$sloc_file" | tr -s ' ' | cut -d' ' -f5)
            echo "$system,$revision,$sloc" >> "$(output-path sloc.csv)"
        else
            echo "$system,$revision,NA" >> "$(output-path sloc.csv)"
        fi
        log "" "$(echo-done)"
    }

    echo system,revision,committer_date_unix,committer_date_readable > "$(output-path date.csv)"
    echo system,revision,source_lines_of_code > "$(output-path sloc.csv)"
    experiment-systems
    join-tables "$(output-path date.csv)" "$(output-path sloc.csv)" > "$(output-csv)"
}
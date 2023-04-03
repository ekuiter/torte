#!/bin/bash

# clones system repositories using git
# shellcheck disable=SC2317
clone-systems() {
    add-system(system, url) {
        log "git-clone: $system"
        if [[ ! -d "$(input-directory)/$system" ]]; then
            log "" "$(echo-progress clone)"
            git clone "$url" "$(input-directory)/$system"
            log "" "$(echo-done)"
        else
            log "" "$(echo-skip)"
        fi
    }

    experiment-subjects
}

# counts number of source lines of codes using cloc
read-statistics() {
    STATISTICS_OPTION=$1

    add-revision(system, revision) {
        log "read-statistics: $system@$revision" "$(echo-progress read)"
        local time
        time=$(git -C "$(input-directory)/$system" --no-pager log -1 -s --format=%ct "$revision")
        local date
        date=$(date -d "@$time" +"%Y-%m-%d")
        echo "$system,$revision,$time,$date" >> "$(output-directory)/date.csv"
        if [[ $STATISTICS_OPTION != skip-sloc ]]; then
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
        log "" "$(echo-done)"
    }

    echo system,revision,committer_date_unix,committer_date_readable > "$(output-directory)/date.csv"
    echo system,revision,source_lines_of_code > "$(output-directory)/sloc.csv"
    experiment-subjects
    join-tables "$(output-directory)/date.csv" "$(output-directory)/sloc.csv" > "$(output-csv)"
}

# adds Linux revisions to the Linux Git repository
# creates an orphaned branch and tag for each revision
# useful to add old revisions before the first Git tag v2.6.12
# by default, tags all revisions between 2.5.45 and 2.6.12, as these use Kconfig
tag-linux-revisions() {
    add-system(system, url=) {
        if [[ $system == linux ]]; then
            if [[ ! -d $(input-directory)/linux ]]; then
                error "Linux has not been cloned yet. Please prepend a stage that runs clone-systems.sh."
            fi

            if git -C linux show-branch v2.6.11 2>&1 | grep -q "No revs to be shown."; then
                git -C linux tag -d v2.6.11 # delete non-commit 2.6.11
            fi

            # could also tag older revisions, but none use Kconfig
            tag-revisions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.5/ 2.5.45
            tag-revisions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/ 2.6.0 2.6.12
            # could also add more granular revisions with minor or patch level after 2.6.12, if necessary

            if [[ $dirty -eq 1 ]]; then
                git -C "$(input-directory)/linux" prune
                git -C "$(input-directory)/linux" gc
            fi
        fi
    }

    tag-revisions(base_uri, start_inclusive=, end_inclusive=) {
        local revisions
        revisions=$(curl -s "$base_uri" \
            | sed 's/.*>\(.*\)<.*/\1/g' | grep .tar.gz | cut -d- -f2 | sed 's/\.tar\.gz//' | sort -V \
            | start-at-revision "$start_inclusive" \
            | stop-at-revision "$end_exclusive")
        for revision in $revisions; do
            if ! git -C "$(input-directory)/linux" tag | grep -q "^v$revision$"; then
                log "tag-revision: linux@$revision" "$(echo-progress add)"
                local date
                date=$(date -d "$(curl -s "$base_uri" | grep "linux-$revision.tar.gz" | \
                    cut -d'>' -f3 | tr -s ' ' | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)" +%s)
                dirty=1
                push "$(input-directory)"
                rm-safe ./*.tar.gz*
                wget -q "$base_uri/linux-$revision.tar.gz"
                tar xzf ./*.tar.gz*
                rm-safe ./*.tar.gz*
                push linux
                git reset -q --hard >/dev/null
                git clean -q -dfx >/dev/null
                git checkout -q --orphan "$revision" >/dev/null
                git reset -q --hard >/dev/null
                git clean -q -dfx >/dev/null
                cp -R "../linux-$revision/." ./
                git add -A >/dev/null
                GIT_COMMITTER_DATE=$date git commit -q --date "$date" -m "v$revision" >/dev/null
                git tag "v$revision" >/dev/null
                pop
                rm-safe "linux-$revision"
                log "" "$(echo-done)"
            else
                log "" "$(echo-skip)"
            fi
        done
    }

    experiment-subjects
}

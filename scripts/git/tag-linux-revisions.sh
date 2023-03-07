#!/bin/bash
# ./tag-linux-revisions.sh
# adds Linux revisions to the Linux Git repository
# creates an orphaned branch and tag for each revision
# useful to add old revisions before the first Git tag v2.6.12
# by default, tags all revisions between 2.5.45 and 2.6.12, as these use Kconfig

add-system() {
    local system=$1
    require-value system
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

tag-revisions() {
    local base_uri=$1
    local start_inclusive=$2
    local end_exclusive=$3
    require-value base_uri
    local revisions
    revisions=$(curl -s "$base_uri" \
        | sed 's/.*>\(.*\)<.*/\1/g' | grep .tar.gz | cut -d- -f2 | sed 's/\.tar\.gz//' | sort -V \
        | start-at-revision "$start_inclusive" \
        | stop-at-revision "$end_exclusive")
    for revision in $revisions; do
        if ! git -C "$(input-directory)/linux" tag | grep -q "^v$revision$"; then
            echo -n "Adding tag for Linux $revision "
            local date
            date=$(date -d "$(curl -s "$base_uri" | grep "linux-$revision.tar.gz" | \
                cut -d'>' -f3 | tr -s ' ' | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)" +%s)
            echo "($(date -d "@$date" +"%Y-%m-%d")) ..."
            dirty=1
            push "$(input-directory)"
            rm -f ./*.tar.gz*
            wget -q "$base_uri/linux-$revision.tar.gz"
            tar xzf ./*.tar.gz*
            rm -f ./*.tar.gz*
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
            rm -rf "linux-$revision"
        else
            echo "Skipping tag for Linux $revision"
        fi
    done
}

# shellcheck source=../../scripts/main.sh
source main.sh load-subjects
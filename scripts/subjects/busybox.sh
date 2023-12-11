#!/bin/bash

add-busybox-kconfig-history(from=, to=) {
    add-system --system busybox --url https://github.com/mirror/busybox
    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

add-busybox-kconfig-history-full() {
    add-system --system busybox --url https://github.com/mirror/busybox
    #for revision in $(git -C "$(input-directory)/busybox-models" log master --format="%h" | tac | head -n350 | tail -n10); do
    #for revision in $(git -C "$(input-directory)/busybox-models" log master --format="%h" | tac | head -n800 | tail -n15); do
    for revision in $(git -C "$(input-directory)/busybox-models" log master --format="%h" | tac); do
        local original_revision
        original_revision=$(git -C "$(input-directory)/busybox-models" rev-list --max-count=1 --format=%B "$revision" | sed '/^commit [0-9a-f]\{40\}$/d')
        add-revision --system busybox-models --revision "${revision}[$original_revision]"
        add-kconfig \
            --system busybox-models \
            --revision "${revision}[$original_revision]" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

generate-busybox-models() {
    git-checkout master "$(input-directory)/busybox" > /dev/null
    git -C "$(output-directory)" init -q
    echo "*.log" >> "$(output-directory)/.gitignore"
    echo "*.err" >> "$(output-directory)/.gitignore"
    local i n
    i=0
    n=$(git -C "$(input-directory)/busybox" log --format="%h" | wc -l)
    git -C "$(input-directory)/busybox" log --format="%h" | tac | while read -r revision; do
        ((i+=1))
        local timestamp
        timestamp=$(git-timestamp busybox "$revision")
        local dir
        dir=$(output-directory)
        rm -rf "${dir:?}/*"
        git-checkout "$revision" "$(input-directory)/busybox" > /dev/null
        if [[ -f "$(input-directory)/busybox/scripts/gen_build_files.sh" ]]; then
            chmod +x "$(input-directory)/busybox/scripts/gen_build_files.sh"
            make -C "$(input-directory)/busybox" gen_build_files >/dev/null 2>&1 || true
        fi
        (cd "$(input-directory)/busybox" || exit; find . -type f -name "*Config.in" -exec cp --parents {} "$(output-directory)" \;)
        mkdir -p "$(output-directory)/scripts/"
        cp -R "$(input-directory)/busybox/scripts/"* "$(output-directory)/scripts/" 2>/dev/null || true
        cp "$(input-directory)/busybox/Makefile"* "$(output-directory)" 2>/dev/null || true
        cp "$(input-directory)/busybox/Rules.mak" "$(output-directory)" 2>/dev/null || true
        git -C "$(output-directory)" add -A
        if [[ $i -eq 1 ]] || ! git -C "$(output-directory)" diff --staged --exit-code '*Config.in' >/dev/null 2>&1; then
            log "[$i/$n] $revision"
            log "" "$(echo-progress gen)"
            GIT_COMMITTER_DATE=$timestamp git -C "$(output-directory)" commit -q -m "$revision" --date "$timestamp" >/dev/null || true
            log "" "$(echo-done)"
        fi
    done
}
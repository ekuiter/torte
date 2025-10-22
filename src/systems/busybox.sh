#!/bin/bash

BUSYBOX_URL=https://github.com/mirror/busybox
BUSYBOX_URL_FORK=https://github.com/ekuiter/torte-busybox

# determine the correct KConfig file for BusyBox at the given revision
find-busybox-kconfig-file(revision) {
    if git -C "$(input-directory)/busybox" cat-file -e "$revision:Config.in" 2>/dev/null; then
        echo Config.in
    else
        echo sysdeps/linux/Config.in
    fi
}

# determine the correct LKC directory for BusyBox at the given revision
find-busybox-lkc-directory(revision) {
    if git -C "$(input-directory)/busybox" cat-file -e "$revision:scripts/kconfig" 2>/dev/null; then
        echo scripts/kconfig
    else
        echo scripts/config
    fi
}

# all versions before 1.00 use CML1 instead of KConfig, which we currently cannot extract, so we start at 1.00
add-busybox-kconfig-history(from=1_00, to=) {
    add-system --system busybox --url "$BUSYBOX_URL"
    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file "$(find-busybox-kconfig-file "$revision")" \
            --lkc-directory "$(find-busybox-lkc-directory "$revision")"
    done
}

# consider all commits that changed the BusyBox feature model (this is a bit convoluted due to the reasons listed in generate-busybox-models)
add-busybox-kconfig-history-commits() {
    add-system --system busybox --url "$BUSYBOX_URL"
    if [[ -f "$(input-directory)/busybox/.generate_busybox_models" ]]; then
        for revision in $(git -C "$(input-directory)/busybox" log master --format="%h" --reverse); do
            local original_revision
            original_revision=$(git -C "$(input-directory)/busybox" rev-list --max-count=1 --format=%B "$revision" | sed '/^commit [0-9a-f]\{40\}$/d')
            add-revision --system busybox --revision "${revision}[$original_revision]"
            add-kconfig \
                --system busybox \
                --revision "${revision}[$original_revision]" \
                --kconfig-file "$(find-busybox-kconfig-file "$revision")" \
                --lkc-directory "$(find-busybox-lkc-directory "$revision")"
        done
    fi
}

# in BusyBox, the feature model is encoded with C comments in the source code, for which KConfig files have to be generated explicitly
# this command creates a new Git repository with these KConfig files
# each revision of the generated repository corresponds to an original revision that changed the feature model
# if you need the original commit hashes, please use add-busybox-kconfig-history (which does not allow analyzing the full history, though)
generate-busybox-models() {
    if [[ $BUSYBOX_GENERATE_MODE == fork ]]; then
        git clone "$BUSYBOX_URL_FORK" "$(output-directory)/busybox"
    elif [[ $BUSYBOX_GENERATE_MODE == generate ]]; then
        git-checkout master "$(input-directory)/busybox" > /dev/null
        local output_directory
        output_directory="$(output-directory)/busybox"
        mkdir -p "$output_directory"
        git -C "$output_directory" init -b master -q
        echo "*.log" >> "$output_directory/.gitignore"
        echo "*.err" >> "$output_directory/.gitignore"
        touch "$output_directory/.generate_busybox_models"
        local i n
        i=0
        n=$(git -C "$(input-directory)/busybox" log --format="%h" | wc -l)
        git -C "$(input-directory)/busybox" log --format="%h" | tac | while read -r revision; do
            ((i+=1))
            local timestamp
            timestamp=$(git-timestamp busybox "$revision")
            local dir
            dir="$output_directory"
            rm -rf "${dir:?}/*"
            git-checkout "$revision" "$(input-directory)/busybox" > /dev/null
            if [[ -f "$(input-directory)/busybox/scripts/gen_build_files.sh" ]]; then
                chmod +x "$(input-directory)/busybox/scripts/gen_build_files.sh"
                make -C "$(input-directory)/busybox" gen_build_files >/dev/null 2>&1 || true
            fi
            (cd "$(input-directory)/busybox" || exit; find . -type f -name "*Config.in" -exec cp --parents {} "$output_directory" \;)
            mkdir -p "$output_directory/scripts/"
            cp -R "$(input-directory)/busybox/scripts/"* "$output_directory/scripts/" 2>/dev/null || true
            cp "$(input-directory)/busybox/Makefile"* "$output_directory" 2>/dev/null || true
            cp "$(input-directory)/busybox/Rules.mak" "$output_directory" 2>/dev/null || true
            git -C "$output_directory" add -A
            if [[ $i -eq 1 ]] || ! git -C "$output_directory" diff --staged --exit-code '*Config.in' >/dev/null 2>&1; then
                log "[$i/$n] $revision"
                log "" "$(echo-progress gen)"
                GIT_COMMITTER_DATE=$timestamp git -C "$output_directory" commit -q -m "$revision" --date "$timestamp" >/dev/null || true
                log "" "$(echo-done)"
            fi
        done
    else
        error "Unknown BusyBox generate mode: $BUSYBOX_GENERATE_MODE"
    fi
}
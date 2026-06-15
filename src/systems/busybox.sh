#!/bin/bash

BUSYBOX_URL=https://github.com/vda-linux/busybox_mirror
BUSYBOX_URL_FORK=https://github.com/ekuiter/torte-busybox

define-system \
    --system busybox \
    --sample-branch master

add-busybox-system(transform...) {
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-busybox
    add-hook-step post-clone-hook post-clone-hook-busybox
    add-system --system busybox --url "$BUSYBOX_URL" --fork-url "$BUSYBOX_URL_FORK" --transform "${transform[@]}"
}

post-clone-hook-busybox(system, transform...) {
    if [[ $system == busybox ]]; then
        local directory
        directory="$(input-directory)/$system"
        # manually tag the release 1.38.0
        local revision_hash=fc71374dfccd46448c62947269a35f1420d7ee28
        if git -C "$directory" rev-parse --quiet --verify "$revision_hash" >/dev/null; then
            git -C "$directory" tag -a 1_38_0 "$revision_hash" -m 1_38_0
        fi
        if array-contains generate-kconfig-commits "${transform[@]}"; then
            generate-kconfig-commits busybox generate-kconfig-commits-busybox master "*Config.in"
        fi
    fi
}

configfix-pre-extraction-hook-busybox(system, revision) {
    if [[ $system == busybox ]]; then
        # the file networking/udhcp/Config.in it does not exist in old revisions, so we have to remove references to it
        if [[ ! -f networking/udhcp/Config.in ]]; then
            find . -type f -exec sed -i '/source\s\+networking\/udhcp\/Config\.in/d' {} \;
        fi
        wrap-source-statements-in-double-quotes \( -name Config.in -o -name Config.src \)
    fi
}

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

add-busybox-kconfig(revision) {
    add-busybox-system
    if [[ ! -d $(input-directory)/busybox ]]; then
        return
    fi
    local revision_without_context
    revision_without_context=$(revision-without-context "$revision")
    add-revision --system busybox --revision "$revision"
    add-kconfig \
        --system busybox \
        --revision "$revision" \
        --kconfig-file "$(find-busybox-kconfig-file "$revision_without_context")" \
        --lkc-directory "$(find-busybox-lkc-directory "$revision_without_context")"
}

# all versions before 1.00 use CML1 instead of KConfig, which we currently cannot extract, so we start at 1.00
add-busybox-kconfig-tags(from=1_00, to=) {
    add-busybox-system
    for revision in $(git-tags busybox | exclude-revision pre alpha rc | start-at-revision "$from" | stop-at-revision "$to"); do
        add-busybox-kconfig --revision "$revision"
    done
}

# considers all commits that changed the BusyBox feature model
# requires a generated KConfig history, because BusyBox encodes parts of the feature model as C comments in source files
# each revision of that generated repository corresponds to an original revision that changed the feature model
add-busybox-kconfig-commits() {
    add-busybox-system generate-kconfig-commits
    if system-has-transform busybox generate-kconfig-commits; then
        for revision in $(git-commits busybox master); do
            add-busybox-kconfig "$(revision-with-context "$revision" "$(git-commit-message busybox "$revision")")"
        done
    fi
}

# transform helper that generates the KConfig files for a BusyBox revision and copies them into the new repository
generate-kconfig-commits-busybox(system, input_directory, output_directory, revision) {
    if [[ -f "$input_directory/scripts/gen_build_files.sh" ]]; then
        chmod +x "$input_directory/scripts/gen_build_files.sh"
        make -C "$input_directory" gen_build_files >/dev/null 2>&1 || true
    fi
    (cd "$input_directory" || exit; find . -type f -name "*Config.in" -exec cp --parents {} "$output_directory" \;)
    mkdir -p "$output_directory/scripts/"
    cp -R "$input_directory/scripts/"* "$output_directory/scripts/" 2>/dev/null || true
    cp "$input_directory/Makefile"* "$output_directory" 2>/dev/null || true
    cp "$input_directory/Rules.mak" "$output_directory" 2>/dev/null || true
}

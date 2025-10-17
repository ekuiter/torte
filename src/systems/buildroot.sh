#!/bin/bash

BUILDROOT_URL=https://github.com/buildroot/buildroot

# determine the correct LKC directory for buildroot at the given revision
find-buildroot-lkc-directory(revision) {
    if git -C "$(input-directory)/buildroot" cat-file -e "$revision:package/config" 2>/dev/null; then
        echo package/config
    else
        echo support/kconfig
    fi
}

# determine the correct LKC directory for buildroot at the given revision
find-buildroot-lkc-output-directory(revision) {
    if git -C "$(input-directory)/buildroot" show "$revision:Makefile" | grep -q 'config: $(BUILD_DIR)/buildroot-config'; then
        echo output/build/buildroot-config
    else
        echo package/config
    fi
}

add-buildroot-kconfig-history(from=, to=) {
    local environment
    # setting these correctly is needed for some versions that refer to these variables in their KConfig files
    environment="BASE_DIR=$(input-directory)/buildroot/output,BUILD_DIR=$(input-directory)/buildroot/output/build,BR2_EXTERNAL=support/dummy-external"
    add-system --system buildroot --url "$BUILDROOT_URL"
    add-hook-step kconfig-pre-binding-hook buildroot "$(to-lambda kconfig-pre-binding-hook-buildroot)"
    add-hook-step kclause-post-binding-hook buildroot "$(to-lambda kclause-post-binding-hook-buildroot)"
    for revision in $(git-tag-revisions buildroot | exclude-revision rc _ 'settings-.*' '\..*\.' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system buildroot --revision "$revision"
        add-kconfig \
            --system buildroot \
            --revision "$revision" \
            --kconfig-file Config.in \
            --lkc-directory "$(find-buildroot-lkc-directory "$revision")" \
            --lkc-output-directory "$(find-buildroot-lkc-output-directory "$revision")" \
            --environment "$environment"
    done
}

kconfig-pre-binding-hook-buildroot(system, revision, lkc_directory=) {
    if [[ $system == buildroot ]]; then
        # with kclause, some buildroot revisions are weird and fail on the first call of make config, succeeding only on the second
        # so, as a hack, we just call it twice here to be sure, it is idempotent after all
        make config >/dev/null 2>&1 || true
    fi
}

kclause-post-binding-hook-buildroot(system, revision) {
    if [[ $system == buildroot ]]; then
        # fix incorrect feature names, which kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
    fi
}
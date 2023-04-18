#!/bin/bash
# The following are templates and convenience functions for working with common experiment subjects.
# Most functions extract (an excerpt of) the tagged history of a kconfig model.
# For customizations (e.g., extract one specific revision or weekly revisions), copy the code to your experiment file and adjust it.

add-axtls-kconfig-history(from=, to=) {
    # use a frozen Git copy of the original SVN repository
    add-system --system axtls --url https://github.com/ekuiter/axTLS
    for revision in $(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to"); do
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --kconfig-binding-files config/scripts/config/*.o
    done
}

add-buildroot-kconfig-history(from=, to=) {
    export BR2_EXTERNAL=support/dummy-external
    export BUILD_DIR=buildroot
    export BASE_DIR=buildroot
    add-system --system buildroot --url https://github.com/buildroot/buildroot
    add-linux-kconfig-binding --revision v4.17
    add-hook-step kconfig-post-checkout-hook buildroot "$(to-lambda kconfig-post-checkout-hook-buildroot)"
    for revision in $(git-tag-revisions buildroot | exclude-revision rc _ 'settings-.*' '\..*\.' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system buildroot --revision "$revision"
        add-kconfig-model \
            --system buildroot \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v4.17)"
    done
}

kconfig-post-checkout-hook-buildroot(system, revision) {
    if [[ $system == buildroot ]]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains \
            .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus \
            .br2-external.in.skeleton .br2-external.in.init
        # ignore generated Kconfig files in buildroot
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \;
    fi
}

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

add-embtoolkit-kconfig-history(from=, to=) {
    add-system --system embtoolkit --url https://github.com/ndmsystems/embtoolkit
    add-hook-step kmax-post-binding-hook embtoolkit "$(to-lambda kmax-post-binding-hook-embtoolkit)"
    for revision in $(git-tag-revisions embtoolkit | exclude-revision rc | grep -v -e '-.*-' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system embtoolkit --revision "$revision"
        add-kconfig \
            --system embtoolkit \
            --revision "$revision" \
            --kconfig-file Kconfig \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

kmax-post-binding-hook-embtoolkit(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kmax interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
    fi
}

add-fiasco-kconfig(revision) {
    add-linux-kconfig-binding --revision v5.0
    add-system --system fiasco --url https://github.com/kernkonzept/fiasco
    add-kconfig-model \
            --system fiasco \
            --revision "$revision" \
            --kconfig-file src/Kconfig \
            --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}

add-freetz-ng-kconfig(revision) {
    add-linux-kconfig-binding --revision v5.0
    add-system --system freetz-ng --url https://github.com/Freetz-NG/freetz-ng
    add-hook-step kconfig-post-checkout-hook freetz-ng "$(to-lambda kconfig-post-checkout-hook-freetz-ng)"
    add-kconfig-model \
        --system freetz-ng \
        --revision "$revision" \
        --kconfig-file config/Config.in \
        --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}

kconfig-post-checkout-hook-freetz-ng(system, revision) {
    if [[ $system == freetz-ng ]]; then
        # ugly hack because freetz-ng is weird
        touch make/Config.in.generated make/external.in.generated make/pkgs/external.in.generated make/pkgs/Config.in.generated config/custom.in
    fi
}

add-linux-system() {
    add-system --system linux --url https://github.com/torvalds/linux
    add-hook-step kconfig-post-checkout-hook linux "$(to-lambda kconfig-post-checkout-hook-linux)"
}

kconfig-post-checkout-hook-linux(system, revision) {
    if [[ $system == linux ]]; then
        replace-linux(regex) { find ./ -type f -name "*Kconfig*" -exec sed -i "s/$regex//g" {} \;; }
        # ignore all constraints that use the newer $(success,...) syntax
        replace-linux "\s*default \$(.*"
        replace-linux "\s*depends on \$(.*"
        replace-linux "\s*def_bool \$(.*"
        # ugly hack for linux 6.0
        replace-linux "\s*def_bool ((.*"
        replace-linux "\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*"
        replace-linux "\s*\$(as-instr,endbr64).*"
    fi
}

linux-tag-revisions() {
    git-tag-revisions linux | exclude-revision tree rc "v.*\..*\..*\..*"
}

add-linux-kconfig(revision, kconfig_binding_file=) {
    add-linux-system
    local arch=x86
    if git -C "$(input-directory)/linux" ls-tree -r "$revision" --name-only | grep -q arch/i386; then
        arch=i386 # in old revisions, x86 is called i386
    fi
    add-revision --system linux --revision "$revision"
    local environment=ARCH=$arch,SRCARCH=$arch,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc
    if [[ -n $kconfig_binding_file ]]; then
        add-kconfig-model \
            --system linux \
            --revision "$revision" \
            --kconfig-file arch/$arch/Kconfig \
            --kconfig-binding-file "$kconfig_binding_file" \
            --environment "$environment"
    else
        add-kconfig \
            --system linux \
            --revision "$revision" \
            --kconfig-file arch/$arch/Kconfig \
            --kconfig-binding-files scripts/kconfig/*.o \
            --environment "$environment"
    fi
}

add-linux-kconfig-binding(revision) {
    add-linux-system
    add-kconfig-binding --system linux --revision "$revision" --kconfig_binding_files scripts/kconfig/*.o
}

linux-kconfig-binding-file(revision) {
    output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux "$revision"
}

add-linux-kconfig-history(from=, to=) {
    # for up to linux 2.6.9, use the kconfig parser of linux 2.6.9 for extraction, as previous versions cannot be compiled
    local first_binding_revision=v2.6.9
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(min-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(min-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig-binding --revision "$first_binding_revision"
        add-linux-kconfig \
            --revision "$revision" \
            --kconfig-binding-file "$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux v2.6.9)"
    done
    # after linux 2.6.9, use the kconfig parser of the respective revision
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(max-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(max-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig --revision "$revision"
    done
}

# adds Linux revisions to the Linux Git repository
# creates an orphaned branch and tag for each revision
# useful to add old revisions before the first Git tag v2.6.12
# by default, tags all revisions between 2.5.45 and 2.6.12, as these use Kconfig
tag-linux-revisions(tag_option=) {
    TAG_OPTION=$tag_option
    
    add-system(system, url=) {
        if [[ -z $DONE_TAGGING_LINUX ]] && [[ $system == linux ]]; then
            if [[ ! -d $(input-directory)/linux ]]; then
                error "Linux has not been cloned yet. Please prepend a stage that clones Linux."
            fi

            if git -C "$(input-directory)/linux" show-branch v2.6.11 2>&1 | grep -q "No revs to be shown."; then
                git -C "$(input-directory)/linux" tag -d v2.6.11 # delete non-commit 2.6.11
            fi

            if [[ $TAG_OPTION != skip-tagging ]]; then
                # could also tag older revisions, but none use Kconfig
                tag-revisions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.5/ 2.5.45
                tag-revisions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/ 2.6.0 2.6.12
                # could also add more granular revisions with minor or patch level after 2.6.12, if necessary
            fi

            if [[ $dirty -eq 1 ]]; then
                git -C "$(input-directory)/linux" prune
                git -C "$(input-directory)/linux" gc
            fi

            DONE_TAGGING_LINUX=y
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

add-toybox-kconfig-history(from=, to=) {
    # do not use this toybox model, it is probably incorrect
    add-system --system toybox --url https://github.com/landley/toybox
    add-hook-step kconfig-post-checkout-hook toybox "$(to-lambda kconfig-post-checkout-hook-toybox)"
    add-linux-kconfig-binding --revision v2.6.12
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig-model \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v2.6.12)"
    done
}

kconfig-post-checkout-hook-toybox(system, revision) {
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
}

add-uclibc-ng-kconfig-history(from=, to=) {
    # environment variable ARCH, VERSION undefined
    add-system --system uclibc-ng --url https://github.com/wbx-github/uclibc-ng
    for revision in $(git-tag-revisions uclibc-ng | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc-ng --revision "$revision"
        add-kconfig \
            --system uclibc-ng \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --kconfig-binding-files extra/config/zconf.tab.o
    done
}
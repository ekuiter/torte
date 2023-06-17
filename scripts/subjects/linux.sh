#!/bin/bash

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

linux-architectures(revision) {
    git -C "$(input-directory)/linux" ls-tree -rd "$revision" --name-only \
        | grep ^arch/ | cut -d/ -f2 | sort | uniq | grep -v '^um$'
}

linux-configs(revision) {
    # match lines in all Kconfig files of the given revision that:
    # - start with 'config' or 'menuconfig' (possibly with leading whitespace)
    # - after which follows an alphanumeric configuration option name
    # then format the result by removing 'config' or 'menuconfig', possible comments, and trimming any whitespace
    # finally, ignore all lines which contain illegal characters (e.g., whitespace)
    git -C "$(input-directory)/linux" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+\w+' "$revision" -- '**/*Kconfig*' \
        | grep -v '^--$' \
        | paste -d: - - \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "linux", $1, $2, $3}' \
        | grep -E ',.*,.*,\w+$'
}

linux-attempt-grouper(file) {
    # shellcheck disable=SC2001
    echo "$file" | sed 's#\(.*\)/linux/.*\[\(.*\)\]\..*#\1.\2#'
}

add-linux-kconfig(revision, architecture=x86, kconfig_binding_file=) {
    if [[ $architecture == x86 ]] && linux-architectures "$revision" | grep -q '^i386$'; then
        architecture=i386 # in old revisions, x86 is called i386
    fi
    if [[ $architecture == um ]]; then
        error "User mode Linux is currently not supported."
    fi
    if [[ $architecture == all ]]; then
        mapfile -t architectures < <(linux-architectures "$revision")
        for architecture in "${architectures[@]}"; do
            add-linux-kconfig "$revision" "$architecture" "$kconfig_binding_file"
        done
        return
    fi
    # ARCH speficies the architecture of the targeted system, SRCARCH the architecture of the compiling system
    # SUBARCH is only taken into account for user mode Linux (um), where it specifies the underlying targeted system architecture
    # here we assume native compilation (no cross-compilation) without user mode Linux
    # srctree is needed by later revisions to access scripts (e.g., in scripts/Kconfig.include)
    # CC and LD are also used in scripts/Kconfig.include
    # KERNELVERSION is generally unused and only defined to avoid warnings
    local environment=SUBARCH=$architecture,ARCH=$architecture,SRCARCH=$architecture,srctree=.,CC=cc,LD=ld,KERNELVERSION=$revision
    # locate the main Kconfig file, which is arch/.../Kconfig in old revisions and Kconfig in new revisions
    local kconfig_file
    kconfig_file=$({ git -C "$(input-directory)/linux" show "$revision:scripts/kconfig/Makefile" | grep "^Kconfig := [^$]" | cut -d' ' -f3; } || true)
    kconfig_file=${kconfig_file:-arch/\$(SRCARCH)/Kconfig}
    kconfig_file=${kconfig_file//\$(SRCARCH)/$architecture}
    add-linux-system
    add-revision --system linux --revision "$revision"
    if [[ -n $kconfig_binding_file ]]; then
        add-kconfig-model \
            --system linux \
            --revision "${revision}[$architecture]" \
            --kconfig-file "$kconfig_file" \
            --kconfig-binding-file "$kconfig_binding_file" \
            --environment "$environment"
    else
        add-kconfig \
            --system linux \
            --revision "${revision}[$architecture]" \
            --kconfig-file "$kconfig_file" \
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

add-linux-kconfig-history(from, to, architecture=x86) {
    add-linux-system
    # for up to linux 2.6.9, use the kconfig parser of linux 2.6.9 for extraction, as previous versions cannot be compiled
    local first_binding_revision=v2.6.9
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(min-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(min-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig-binding --revision "$first_binding_revision"
        add-linux-kconfig \
            --revision "$revision" \
            --architecture "$architecture" \
            --kconfig-binding-file "$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux "$first_binding_revision")"
    done
    # after linux 2.6.9, use the kconfig parser of the respective revision
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(max-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(max-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig --revision "$revision" --architecture "$architecture"
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

    tag-revisions(base_uri, start_inclusive=, end_exclusive=) {
        local revisions
        revisions=$(curl -s "$base_uri" \
            | sed 's/.*>\(.*\)<.*/\1/g' | grep .tar.gz | cut -d- -f2 | sed 's/\.tar\.gz//' | sort -V \
            | start-at-revision "$start_inclusive" \
            | stop-at-revision "$end_exclusive")
        for revision in $revisions; do
            if ! git -C "$(input-directory)/linux" tag | grep -q "^v$revision$"; then
                log "tag-revision: linux@$revision" "$(echo-progress add)"
                local date
                date=$(date -d "$(curl -s "$base_uri" | grep "linux-$revision.tar.gz" \
                    | cut -d'>' -f3 | tr -s ' ' | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)" +%s)
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

# extracts code names of linux revisions, just because it's fun :-)
read-linux-names() {
    add-revision(system, revision) {
        if [[ $system == linux ]]; then
            log "read-linux-name: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/linux ]]; then
                error "Linux has not been cloned yet. Please prepend a stage that clones Linux."
            fi
            local name
            name=$({ git -C "$(input-directory)/linux" show "$revision:Makefile" | grep -oP "^NAME = \K.*"; } || true)
            name=${name:-NA}
            echo "$system,$revision,$name" >> "$(output-csv)"
            log "" "$(echo-done)"
        fi
    }

    echo system,revision,name > "$(output-csv)"
    experiment-subjects
}

# extracts architectures of linux revisions
read-linux-architectures() {
    add-revision(system, revision) {
        if [[ $system == linux ]]; then
            log "read-linux-architectures: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/linux ]]; then
                error "Linux has not been cloned yet. Please prepend a stage that clones Linux."
            fi
            local architectures
            mapfile -t architectures < <(linux-architectures "$revision")
            for architecture in "${architectures[@]}"; do
                echo "$system,$revision,$architecture" >> "$(output-csv)"
            done
            log "" "$(echo-done)"
        fi
    }

    echo system,revision,architecture > "$(output-csv)"
    experiment-subjects
}

# extracts configuration options of linux revisions
read-linux-configs() {
    add-revision(system, revision) {
        if [[ $system == linux ]]; then
            log "read-linux-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/linux ]]; then
                error "Linux has not been cloned yet. Please prepend a stage that clones Linux."
            fi
            local configs
            linux-configs "$revision" >> "$(output-csv)"
            log "" "$(echo-done)"
        fi
    }

    echo system,revision,kconfig-file,config,prompt > "$(output-csv)"
    experiment-subjects
}
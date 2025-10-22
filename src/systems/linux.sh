#!/bin/bash

LINUX_URL_FORK=https://github.com/ekuiter/torte-linux
LINUX_URL_ORIGINAL=https://github.com/torvalds/linux

add-linux-system() {
    if [[ $LINUX_CLONE_MODE == filter ]]; then
        add-hook-step post-clone-hook linux "$(to-lambda post-clone-hook-linux)"
    fi
    add-hook-step kconfig-post-checkout-hook linux "$(to-lambda kconfig-post-checkout-hook-linux)"
    add-hook-step kconfig-pre-binding-hook linux "$(to-lambda kconfig-pre-binding-hook-linux)"
    if [[ $LINUX_CLONE_MODE == fork ]]; then
        local url="$LINUX_URL_FORK"
    elif [[ $LINUX_CLONE_MODE == original ]] || [[ $LINUX_CLONE_MODE == filter ]]; then
        local url="$LINUX_URL_ORIGINAL"
    else
        error "Unknown Linux clone mode: $LINUX_CLONE_MODE"
    fi
    add-system --system linux --url "$url"
}

post-clone-hook-linux(system, revision) {
    if [[ $system == linux ]]; then
        # we need to purge a few files from the git history, which cannot be checked out on case-insensitive file systems. this changes all commit hashes.
        # we don't need these files anyway for feature-model extraction
        # see https://github.com/torvalds/linux/tree/v3.0/include/linux/netfilter_ipv4
        # and https://github.com/ekuiter/torte/blob/637bdaf85d8558ccb491abe725e312488d101fc9/src/systems/linux.sh
        # if you need the original commit hashes, please use LINUX_CLONE_MODE=original
        git -C "$(input-directory)/linux" filter-repo --force --invert-paths \
            --path-glob 'include/*/xt_*' \
            --path-glob 'include/*/ipt_*' \
            --path-glob 'include/*/ip6t_*' \
            --path-glob 'net/*/xt_*' \
            --path-glob 'net/*/ipt_*' \
            --path-glob 'net/*/ip6t_*' \
            --path-glob '*/Z6.0+pooncelock+poonceLock+pombonce*' \
            --path-glob '*/Z6.0+pooncelock+pooncelock+pombonce*' \
            --path-glob 'Documentation/io-mapping.txt'
    fi
}

kconfig-post-checkout-hook-linux(system, revision) {
    if [[ $system == linux ]]; then
        replace-linux(regex, replacement=) { find ./ -type f -name "*Kconfig*" -exec sed -i "s/$regex/$replacement/g" {} \;; }
        # ignore all constraints that use the newer $(success,...) syntax
        replace-linux "\s*default \$(.*" # default values are not translated into the formula anyway, so we can ignore them
        replace-linux "\s*depends on \$(.*" # for simplicity, we ignore machine-dependent dependencies, which describe inter-machine variability
        replace-linux "def_bool \$(.*" 'bool "machine-dependent feature"' # as above, ignore default value and translate as normal Boolean feature
        # ugly hack for linux 6.0 due to multiline def_bool (https://github.com/torvalds/linux/blob/v6.0/arch/x86/Kconfig#L1834)
        replace-linux "def_bool ((.*" 'bool "machine-dependent feature"'
        replace-linux "\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*"
        replace-linux "\s*\$(as-instr,endbr64).*"
    fi
}

kconfig-pre-binding-hook-linux(system, revision, lkc_directory=) {
    if [[ $system == linux ]]; then
        if [[ -f scripts/kconfig/Makefile ]]; then
            # until v2.6.9, LKC builds the shared library libkconfig.so and expects it to be present during extraction
            # the following change enforces static compilation instead, as it is also done in v2.6.10 and later
            sed -i 's/libkconfig.so/zconf.tab.o/g' scripts/kconfig/Makefile
            # also in some versions until v2.6.9, compiling mconf fails
            # as we don't need it anyway, we disable it here
            sed -i 's/^host-progs	:=.*$/host-progs	:= conf/g' scripts/kconfig/Makefile
        fi
        if [[ -f scripts/Makefile ]]; then
            # until v2.5.75, the Makefile tries to build modpost during kconfig extraction, which fails
            # as we don't need it anyway, we disable it here
            sed -i 's/^\(host-progs	:= .*\) modpost/\1/' scripts/Makefile
        fi
        if [[ -f Makefile ]]; then
            # until v2.5.70, ARCH is set using ':=', which prevents overriding it with an environment variable
            sed -i 's/ARCH := $(SUBARCH)/ARCH ?= $(SUBARCH)/' Makefile
        fi
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
    # note that this does not exclude the architecture um as done in other functions
    git -C "$(input-directory)/linux" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Kconfig*' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "linux", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

linux-config-types(revision) {
    # similar to linux-configs, reads all configuration options, but also tries to read their types from the succeeding line
    # note that this is less accurate than linux-configs due to the complexity of the regular expressions
    # also, this does not exclude the architecture um as done in other functions
    git -C "$(input-directory)/linux" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Kconfig*' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Kconfig[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Kconfig[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "linux", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}

linux-attempt-grouper(file) {
    # group solving attempts by architecture (so skipping after a certain number of attempts is scoped to a given architecture)
    # shellcheck disable=SC2001
    echo "$file" | sed 's#\(.*\)/linux/.*\[\(.*\)\]\..*#\1.\2#'
}

add-linux-kconfig(revision, architecture=x86, lkc_binding_file=) {
    if [[ $architecture == x86 ]] && linux-architectures "$revision" | grep -q '^i386$'; then
        architecture=i386 # in old revisions, x86 is called i386
    fi
    if [[ $architecture == um ]]; then
        error "User mode Linux is currently not supported."
    fi
    if [[ $architecture == all ]]; then
        mapfile -t architectures < <(linux-architectures "$revision")
        for architecture in "${architectures[@]}"; do
            add-linux-kconfig "$revision" "$architecture" "$lkc_binding_file"
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
    if [[ -n $lkc_binding_file ]]; then
        add-kconfig-model \
            --system linux \
            --revision "${revision}[$architecture]" \
            --kconfig-file "$kconfig_file" \
            --lkc-binding-file "$lkc_binding_file" \
            --environment "$environment"
    else
        add-kconfig \
            --system linux \
            --revision "${revision}[$architecture]" \
            --kconfig-file "$kconfig_file" \
            --lkc-directory scripts/kconfig \
            --environment "$environment"
    fi
}

add-linux-lkc-binding(revision) {
    add-linux-system
    # explicitly set the architecture to an arbitrary valid one, which is not used to compile the binding
    # older Linux versions otherwise default to the host machine architecture, which may not be available (e.g., aarch64)
    # we use x86/i386 here as it is available in every revision
    local architecture=x86
    if linux-architectures "$revision" | grep -q '^i386$'; then
        architecture=i386
    fi
    local environment=SUBARCH=$architecture,ARCH=$architecture,SRCARCH=$architecture
    add-lkc-binding --system linux --revision "$revision" --lkc-directory scripts/kconfig --environment "$environment"
}

linux-lkc-binding-file(revision) {
    output-path "$LKC_BINDINGS_DIRECTORY" linux "$revision"
}

add-linux-kconfig-revisions(revisions=, architecture=x86) {
    add-linux-system
    # for up to linux 2.5.70, use LKC of linux 2.5.71 for extraction, as previous versions cannot be easily compiled
    # this is because LKC was very much under development in between October 2002 and June 2003 (for example, property->expr does not even exist until 2.5.71)
    # in theory, we could try to guess how to adapt our bindings, but this might easily introduce mistakes and would be a lot of effort due to the many changes
    # to work with LKC 2.5.71, we require that old revisions are tagged (tag-linux-revisions)
    local first_binding_revision=v2.5.71
    if [[ -z $revisions ]] || ! git -C "$(input-directory)/linux" tag | grep -q "^$first_binding_revision$"; then
        return
    fi
    local first_binding_timestamp current_timestamp
    first_binding_timestamp=$(git-timestamp linux "$first_binding_revision")
    while read -r revision; do
        current_timestamp=$(git-timestamp linux "$revision")
        if [[ $current_timestamp -lt $first_binding_timestamp ]]; then
            add-linux-lkc-binding --revision "$first_binding_revision"
            add-linux-kconfig \
                --revision "$revision" \
                --architecture "$architecture" \
                --lkc-binding-file "$(output-path "$LKC_BINDINGS_DIRECTORY" linux "$first_binding_revision")"
        else
            add-linux-kconfig --revision "$revision" --architecture "$architecture"
        fi
    done < <(printf '%s\n' "$revisions")
}

add-linux-kconfig-history(from=, to=, architecture=x86) {
    add-linux-kconfig-revisions "$(linux-tag-revisions \
        | start-at-revision "$from" \
        | stop-at-revision "$to")" \
        "$architecture"
}

add-linux-kconfig-sample(interval, architecture=x86) {
    add-linux-kconfig-revisions "$(memoize git-sample-revisions linux "$interval" master)" "$architecture"
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

    experiment-systems
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
    experiment-systems
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
    experiment-systems
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
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)
            echo system,revision,kconfig_file,config >> "$configs"
            echo system,revision,kconfig_file,config,type >> "$config_types"
            linux-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"
            linux-config-types "$revision" >> "$config_types"
            if [[ ! -f $(output-file types.csv) ]]; then
                join-tables "$configs" "$config_types" | head -n1 > "$(output-file types.csv)"
            fi
            join-tables "$configs" "$config_types" | tail -n+2 >> "$(output-file types.csv)"
            log "" "$(echo-done)"
            rm-safe "$configs" "$config_types"
        fi
    }

    echo system,revision,kconfig_file,config > "$(output-csv)"
    experiment-systems
}
#!/bin/bash

PTXDIST_URL=https://git.pengutronix.de/git/ptxdist

define-system \
    --system ptxdist \
    --kconfig-file config/Kconfig \
    --lkc-directory scripts/kconfig \
    --lkc-target kconfig \
    --environment CONFIG_=PTXCONF_,PTXDIST_VERSION_FULL=0,CONFIGFILE_VERSION=0 \
    --sample-branch master

add-ptxdist-system() {
    add-hook-step post-clone-hook post-clone-hook-ptxdist
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-ptxdist
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-ptxdist
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-ptxdist
    add-system --system ptxdist --url "$PTXDIST_URL"
}

add-ptxdist-kconfig-tags(from=, to=) {
    add-ptxdist-kconfig-revisions "$(git-tags ptxdist | start-at-revision "$from" | stop-at-revision "$to")"
}

kconfig-post-checkout-hook-ptxdist(system, revision) {
    if [[ $system == ptxdist ]]; then
        if ! has-command gawk; then
            apt-get install -y --allow-unauthenticated gawk 2>/dev/null
        fi
        generate-ptxdist-kconfig-sections
    fi
}

kconfig-pre-binding-hook-ptxdist(system, revision, lkc_directory=) {
    if [[ $system == ptxdist ]]; then
        write-ptxdist-makefiles
        patch-ptxdist-lkc-sources
        patch-ptxdist-kconfig-target
    fi
}

generate-ptxdist-kconfig-sections() {
    if [[ -f scripts/lib/ptxd_lib_kgen.sh ]]; then
        # ptxdist generates generated/*.in from section markers in rules/*.in
        # normally this is done by the ptxdist frontend before running kconfig
        # here we call the same helper directly and keep its temp directory
        # older helpers delete PTX_KGEN_DIR before writing it
        check_pipe_status() { return 0; }
        export -f check_pipe_status
        export PTXDIST_TOPDIR=$(pwd -P)
        export PTXDIST_PATH_RULES=$PTXDIST_TOPDIR/rules
        export PTXDIST_PATH_PLATFORMS=$PTXDIST_TOPDIR/platforms
        export PTXDIST_TEMPDIR=$PTXDIST_TOPDIR/.ptxdist-torte

        source scripts/lib/ptxd_lib_kgen.sh
        ptxd_kgen ptx

        # expose the generated kconfig sections where config/kconfig expects them
        rm -rf generated
        if [[ -d $PTX_KGEN_DIR/generated ]]; then
            ln -s "$PTX_KGEN_DIR/generated" generated
        elif [[ -d $PTX_KGEN_DIR/ptx ]]; then
            ln -s "$PTX_KGEN_DIR/ptx" generated
        elif [[ -d $PTX_KGEN_DIR ]]; then
            ln -s "$PTX_KGEN_DIR" generated
        fi
    else
        write-ptxdist-generated-sections
    fi

    write-ptxdist-missing-source-files
}

write-ptxdist-generated-sections() {
    # old ptxdist revisions have generated/*.in includes but no kgen helper
    # group package snippets by their section markers like the later helper does
    rm -rf generated
    mkdir -p generated
    find rules platforms -type f -name '*.in' 2>/dev/null \
        | sort \
        | while read -r source_file; do
            sed -nE 's/^##[[:space:]]*SECTION=([^[:space:]]+).*/\1/p' "$source_file" \
                | while read -r section; do
                    printf 'source "%s"\n' "$source_file" >> "generated/$section.in"
                done
        done
}

write-ptxdist-missing-source-files() {
    # project-specific fragments are normally supplied by the ptxdist frontend
    # empty files model the plain checkout without extra project or layer rules
    local changed kconfig source_file
    changed=y
    while [[ $changed == y ]]; do
        changed=n
        while read -r kconfig; do
            while read -r source_file; do
                [[ -n $source_file ]] || continue
                case $source_file in
                    generated/*|rules/*.in|platforms/*.in|config/*.in|workspace/rules/*.in) ;;
                    *) continue ;;
                esac
                if [[ ! -e $source_file ]]; then
                    mkdir -p "$(dirname "$source_file")"
                    : > "$source_file"
                    changed=y
                fi
            done < <(sed -nE 's/^[[:space:]]*source[[:space:]]+"([^"]+)".*$/\1/p' "$kconfig")
        done < <(find config rules platforms generated -type f \( -name 'Kconfig' -o -name '*.in' \) 2>/dev/null)
    done
}

patch-ptxdist-lkc-sources() {
    [[ -d scripts/kconfig ]] || return 0
    (
        cd scripts/kconfig || exit

        # old gperf output defines kconf_id_lookup as extern inline
        # newer compilers may then not emit a real function body
        # make it static inline so references from the parser link again
        for hash in zconf.hash.c zconf.hash.c_shipped; do
            [[ ! -s $hash ]] || perl -0pi -e 's/__inline\n#endif\nstruct kconf_id/static __inline\n#endif\nstruct kconf_id/g' "$hash"
        done
    )
}

write-ptxdist-makefiles() {
    # some ptxdist revisions only ship makefile.in files
    # fill the few configure substitutions needed to build scripts/kconfig/conf
    if [[ -f Makefile.in && ! -f Makefile ]]; then
        sed \
            -e "s|@abs_srcdir@|$(pwd -P)|g" \
            -e 's|@BASH@|/bin/bash|g' \
            Makefile.in > Makefile
    fi
    if [[ -f scripts/kconfig/Makefile.in && ! -f scripts/kconfig/Makefile ]]; then
        sed \
            -e 's|@CC@|cc|g' \
            -e 's|@CXX@|c++|g' \
            -e 's|@CFLAGS@|-O0 -g0 -fcommon|g' \
            -e 's|@CXXFLAGS@|-O0 -g0|g' \
            -e 's|@CPPFLAGS@||g' \
            -e 's|@LDFLAGS@||g' \
            -e 's|@YACC@|bison|g' \
            -e 's|@LEX@|flex|g' \
            -e 's|@BUILD_NCONF_TRUE@|#|g' \
            scripts/kconfig/Makefile.in > scripts/kconfig/Makefile
    fi
}

patch-ptxdist-kconfig-target() {
    [[ -f Makefile ]] || return 0

    # kconfig is the native ptxdist target for building kconfig tools
    # make it stop after conf, because extraction never needs mconf or nconf
    if grep -q '^kconfig:' Makefile; then
        perl -0pi -e 's/kconfig:\n(?:\t.*\n)+/kconfig:\n\t\$(MAKE) -C "\$(abs_srcdir)\/scripts\/kconfig" conf\n/s' Makefile
    else
        cat >> Makefile <<'EOF'

kconfig:
	$(MAKE) -C "$(abs_srcdir)/scripts/kconfig" conf
EOF
    fi
}

kclause-post-binding-hook-ptxdist(system, revision, date_prefix=) {
    if [[ $system == ptxdist ]]; then
        # PTXdist's own parser prefix is PTXCONF_.  Keep punctuation
        # normalization for generated/package-rich feature names in line with
        # other build-system subjects before downstream SMT/DIMACS stages.
        sed -i 's/-/_/g; s#/#_#g; s/[.]/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"
    fi
}

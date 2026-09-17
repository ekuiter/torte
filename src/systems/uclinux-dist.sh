#!/bin/bash

UCLINUX_DIST_URL=https://github.com/scs/uclinux

define-system \
    --system uclinux-dist \
    --sample-branch master

add-uclinux-dist-system(transform...) {
    if is-array-empty transform; then
        transform=(filter-case-insensitive)
    fi
    add-hook-step post-clone-hook post-clone-hook-uclinux-dist
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-uclinux-dist
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-uclinux-dist
    add-system --system uclinux-dist --url "$UCLINUX_DIST_URL" --transform "${transform[@]}"
}

add-uclinux-dist-kconfig(revision) {
    add-uclinux-dist-system
    if [[ ! -d $(input-directory)/uclinux-dist ]]; then
        return
    fi

    local revision_commit safe_revision
    revision_commit=$(git -C "$(input-directory)/uclinux-dist" rev-parse --verify "$revision^{commit}" 2>/dev/null || echo "$revision")
    if [[ $revision_commit != "$revision" ]] && [[ $revision == *"/"* ]]; then
        # keep slash-bearing tags usable as path-safe contexts
        safe_revision=$(revision-with-context "$revision_commit" "${revision//\//_}")
    else
        safe_revision=$revision
    fi

    # keep filtering, generated root, and old-lkc target in one place
    add-revision --system uclinux-dist --revision "$safe_revision"
    add-kconfig \
        --system uclinux-dist \
        --revision "$safe_revision" \
        --kconfig-file Kconfig.torte \
        --lkc-directory config/kconfig \
        --lkc-target torte-conf \
        --environment SCRIPTSDIR=config/kconfig,CONFIG_SHELL=/bin/bash,HOSTCC=gcc,HOSTCXX=g++
}

add-uclinux-dist-kconfig-tags(from=, to=) {
    add-uclinux-dist-kconfig-revisions "$(uclinux-dist-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

uclinux-dist-tags() {
    git-tags uclinux-dist | grep -E '^release/v[0-9]+[.][0-9]+(-p[0-9]+)?$'
}

post-clone-hook-uclinux-dist(system, transform...) {
    if [[ $system == uclinux-dist ]]; then
        if array-contains filter-case-insensitive "${transform[@]}"; then
            filter-case-insensitive-uclinux-dist
        fi
    fi
}

filter-case-insensitive-uclinux-dist() {
    # remove unused payload collisions and rename the second-stage root
    git -C "$(input-directory)/uclinux-dist" filter-repo --force --invert-paths \
        --path lib/Libnet/makefile \
        --path lib/libnl/makefile \
        --path lib/libpam/Linux-PAM-0.99.3.0/CHANGELOG \
        --path user/asterisk-addons/makefile \
        --path user/blkfin-apps/ndso/web_ndso/images/ADI2.JPG \
        --path user/dnsmasq2/makefile \
        --path user/freeradius/makefile \
        --path user/gnugk/readme.txt \
        --path user/hping/makefile \
        --path user/blkfin-apps/w3cam/w3cam-0.7.2/SAMPLES \
        --path user/iptables/iptables-1.4.0/extensions/libip6t_HL.c \
        --path user/iptables/iptables-1.4.0/extensions/libip6t_HL.man \
        --path user/iptables/iptables-1.4.0/extensions/libipt_ECN.c \
        --path user/iptables/iptables-1.4.0/extensions/libipt_ECN.man \
        --path user/iptables/iptables-1.4.0/extensions/libipt_SET.c \
        --path user/iptables/iptables-1.4.0/extensions/libipt_SET.man \
        --path user/iptables/iptables-1.4.0/extensions/libipt_TOS.c \
        --path user/iptables/iptables-1.4.0/extensions/libipt_TOS.man \
        --path user/iptables/iptables-1.4.0/extensions/libipt_TTL.c \
        --path user/iptables/iptables-1.4.0/extensions/libipt_TTL.man \
        --path user/iptables/iptables-1.4.0/extensions/libxt_CONNMARK.c \
        --path user/iptables/iptables-1.4.0/extensions/libxt_CONNMARK.man \
        --path user/iptables/iptables-1.4.0/extensions/libxt_DSCP.c \
        --path user/iptables/iptables-1.4.0/extensions/libxt_DSCP.man \
        --path user/iptables/iptables-1.4.0/extensions/libxt_MARK.c \
        --path user/iptables/iptables-1.4.0/extensions/libxt_TCPMSS.c \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter/xt_CONNMARK.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter/xt_DSCP.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter/xt_MARK.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter/xt_TCPMSS.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter_ipv4/ipt_ECN.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter_ipv4/ipt_TTL.h \
        --path user/iptables/iptables-1.4.0/include/linux/netfilter_ipv6/ip6t_HL.h \
        --path user/microwin/nxlib/nxlib-0.45/X11/include/X11/bitmaps/Stipple \
        --path user/perl/Cross/makefile \
        --path user/pptp/makefile \
        --path-rename config/Kconfig:config/Kconfig.torte
}

kconfig-post-checkout-hook-uclinux-dist(system, revision) {
    if [[ $system == uclinux-dist ]]; then
        prepare-uclinux-dist-kconfig "$revision"
    fi
}

kconfig-pre-binding-hook-uclinux-dist(system, revision, lkc_directory=) {
    if [[ $system == uclinux-dist ]]; then
        prepare-uclinux-dist-kconfig "$revision"
    fi
}

prepare-uclinux-dist-kconfig(revision) {
    write-uclinux-dist-vendor-kconfig
    write-uclinux-dist-torte-root "$revision"
    normalize-uclinux-dist-kconfig-sources
    patch-uclinux-dist-old-lkc
    write-uclinux-dist-minimal-target
}

write-uclinux-dist-vendor-kconfig() {
    mkdir -p vendors
    {
        find vendors -mindepth 2 '(' -name .svn -prune ')' -o -type f -name Kconfig -print \
            | sed -E 's#^(.+)$#source \1#'
    } > vendors/Kconfig.torte
}

write-uclinux-dist-torte-root(revision) {
    if [[ -x config/mkconfig ]]; then
        chmod u+x config/mkconfig
        if ! config/mkconfig > Kconfig.torte 2>/dev/null; then
            : > Kconfig.torte
        fi
    else
        git show "$revision:config/Kconfig.torte" 2>/dev/null | perl -pe 's#source\s+"?\.\./([^"\s]*)"?#source $1#' > Kconfig.torte
    fi

    # append second-stage lib/user/vendor sources to the generated root
    # this old lexer expects unquoted source paths
    cat >> Kconfig.torte <<'EOF'

menu "Application/Library Configuration"
source lib/Kconfig
source user/Kconfig
source vendors/Kconfig.torte
endmenu
EOF
}

normalize-uclinux-dist-kconfig-sources() {
    for source_dir in lib user vendors; do
        [[ -d $source_dir ]] || continue
        find "$source_dir" -type f \( -name Kconfig -o -name Config.in \) \
            -exec perl -pi -e 's#^([ \t]*)source[ \t]+"?\.\./([^" \t]*)"?[ \t]*$#$1source $2#; s#^([ \t]*)source[ \t]+"([^" \t]+)"[ \t]*$#$1source $2#' {} \;
    done
}

patch-uclinux-dist-old-lkc() {
    [[ -d config/kconfig ]] || return 0
    pushd config/kconfig >/dev/null || return 0

    if [[ ! -s zconf.tab.c && -f zconf.tab.c_shipped ]]; then
        cp zconf.tab.c_shipped zconf.tab.c
    fi
    if [[ ! -s lex.zconf.c && -f lex.zconf.c_shipped ]]; then
        cp lex.zconf.c_shipped lex.zconf.c
    fi
    if [[ ! -s zconf.hash.c && -f zconf.hash.c_shipped ]]; then
        cp zconf.hash.c_shipped zconf.hash.c
    fi

    # old gperf output can lose kconf_id_lookup at link time
    for hash_file in zconf.hash.c zconf.hash.c_shipped; do
        [[ -f $hash_file ]] || continue
        perl -pi -e 's/^__inline$/static __inline/' "$hash_file"
        perl -0pi -e 's/^static unsigned int\n(kconf_id_hash)/unsigned int\n$1/m' "$hash_file"
    done
    rm -f conf *.o

    popd >/dev/null
}

write-uclinux-dist-minimal-target() {
    # use a narrow conf-only target after the root model is generated
    cat > Makefile <<'EOF'
.PHONY: torte-conf
torte-conf:
	$(MAKE) -C config/kconfig conf
EOF
}

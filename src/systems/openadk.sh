#!/bin/bash

OPENADK_URL=https://github.com/wbx-github/openadk

# openadk uses a linux-derived lkc in adk/config
# Config.in needs generated target and package fragments
# generate those locally and build only adk/config/conf
define-system \
    --system openadk \
    --kconfig-file Config.in \
    --lkc-directory adk/config \
    --lkc-target torte-conf \
    --environment ADK_TOPDIR=.,TOPDIR=.,HOST_CC=cc,CC_FOR_BUILD=cc,HOST_CFLAGS=-O0,HOST_CXX=c++,HOST_CXXFLAGS=-O0,CURSES_CFLAGS=,CURSES_LIBS=-lncurses,OS_FOR_BUILD=linux,CONFIG_=ADK_ \
    --sample-branch master

add-openadk-system(transform...) {
    if is-array-empty transform; then
        transform=(filter-case-insensitive)
    fi
    add-hook-step post-clone-hook post-clone-hook-openadk
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-openadk
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-openadk
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-openadk
    add-system --system openadk --url "$OPENADK_URL" --transform "${transform[@]}"
}

post-clone-hook-openadk(system, transform...) {
    if [[ $system == openadk ]] && array-contains filter-case-insensitive "${transform[@]}"; then
        filter-case-insensitive-openadk
    fi
}

filter-case-insensitive-openadk() {
    # this non-kconfig patch trips checkout on macos-mounted docker worktrees
    git -C "$(input-directory)/openadk" filter-repo --force --invert-paths \
        --path package/ipset/patches/patch-kernel_ipt_set_c
}

kconfig-post-checkout-hook-openadk(system, revision) {
    if [[ $system == openadk ]]; then
        prepare-openadk-kconfig
    fi
}

kconfig-pre-binding-hook-openadk(system, revision, lkc_directory=) {
    if [[ $system == openadk ]]; then
        prepare-openadk-kconfig
    fi
}

prepare-openadk-kconfig() {
    write-openadk-prereq-mk
    run-openadk-menu-generators
    write-openadk-host-prereq-kconfig
    write-openadk-generated-source-fallbacks
    patch-openadk-old-lkc
    write-openadk-minimal-lkc-target
}

write-openadk-prereq-mk() {
    local topdir
    topdir=$(pwd -P)

    cat > prereq.mk <<EOF
ADK_TOPDIR:=$topdir
BASH:=/bin/bash
SHELL:=/bin/bash
GMAKE:=make
MAKE:=make
OS_FOR_BUILD:=linux
HOST_CC:=cc
HOST_CFLAGS:=-O0 -g0 -fcommon
HOST_CXX:=c++
HOST_CXXFLAGS:=-O0 -g0 -fcommon
CURSES_CFLAGS:=
CURSES_LIBS:=-lncurses
LANGUAGE:=C
LC_ALL:=C
export ADK_TOPDIR BASH SHELL
EOF
}

run-openadk-menu-generators() {
    # generate the target and task fragments sourced by Config.in
    if [[ -x scripts/create-menu || -f scripts/create-menu ]]; then
        /bin/bash scripts/create-menu >/dev/null 2>&1 || true
    else
        # old revisions split the same menu generation across two scripts
        [[ ! -f scripts/create-sys ]] || /bin/bash scripts/create-sys >/dev/null 2>&1 || true
        [[ ! -f scripts/update-sys ]] || /bin/bash scripts/update-sys >/dev/null 2>&1 || true
        write-openadk-old-target-menu-wrappers
    fi

    # pkgmaker translates package metadata to kconfig fragments
    if [[ -f adk/tools/pkgmaker.c && -f adk/tools/sortfile.c && -f adk/tools/strmap.c ]]; then
        cc -O0 -g0 -fcommon -w -o adk/tools/pkgmaker \
            adk/tools/pkgmaker.c adk/tools/sortfile.c adk/tools/strmap.c >/dev/null 2>&1 || true
    fi
    if [[ -x adk/tools/pkgmaker ]]; then
        mkdir -p package/pkgconfigs.d package/pkglist.d
        adk/tools/pkgmaker >/dev/null 2>&1 || true
    fi
}

write-openadk-old-target-menu-wrappers() {
    mkdir -p target/config
    if [[ ! -e target/config/Config.in.arch && -e target/config/Config.in.arch.choice ]]; then
        cat > target/config/Config.in.arch <<'EOF'
source "target/config/Config.in.arch.default"
source "target/config/Config.in.arch.choice"
EOF
    fi
    if [[ ! -e target/config/Config.in.system && -e target/config/Config.in.system.choice ]]; then
        cat > target/config/Config.in.system <<'EOF'
source "target/config/Config.in.system.default"
source "target/config/Config.in.system.choice"
EOF
    fi
}

write-openadk-host-prereq-kconfig() {
    mkdir -p target/config
    cat > target/config/Config.in.prereq <<'EOF'
config ADK_HOST_BUILD_TOOLS
	bool
	default y

config ADK_HOST_LINUX
	bool
	default y
EOF
}

write-openadk-generated-source-fallbacks() {
    # empty generated files model missing project-specific fragments
    local changed kconfig source_file
    changed=y
    while [[ $changed == y ]]; do
        changed=n
        while read -r kconfig; do
            while read -r source_file; do
                [[ -n $source_file && $source_file != *'$'* ]] || continue
                if [[ ! -e $source_file ]]; then
                    mkdir -p "$(dirname "$source_file")"
                    : > "$source_file"
                    changed=y
                fi
            done < <(sed -nE 's/^[[:space:]]*source[[:space:]]+"?([^"[:space:]]+)"?.*$/\1/p' "$kconfig")
        done < <(find . -type f \( -name 'Config.in' -o -name 'Config.in.*' \) | sed 's#^\./##')
    done
}

patch-openadk-old-lkc() {
    [[ -d adk/config ]] || return 0
    (
        cd adk/config || exit

        # materialize shipped parser files before conf.c is replaced
        [[ -s zconf.tab.c || ! -f zconf.tab.c_shipped ]] || cp zconf.tab.c_shipped zconf.tab.c
        [[ -s zconf.tab.h || ! -f zconf.tab.h_shipped ]] || cp zconf.tab.h_shipped zconf.tab.h
        [[ -s zconf.hash.c || ! -f zconf.hash.c_shipped ]] || cp zconf.hash.c_shipped zconf.hash.c
        [[ -s lex.zconf.c || ! -f lex.zconf.c_shipped ]] || cp lex.zconf.c_shipped lex.zconf.c
    )
}

write-openadk-minimal-lkc-target() {
    [[ -f Makefile ]] || return 0
    if ! grep -q '^torte-conf:' Makefile; then
        cat >> Makefile <<'EOF'

# torte: build only openadk's revision-local kconfig frontend
.PHONY: torte-conf
torte-conf:
	$(MAKE) --no-print-directory ADK_TOPDIR=$(CURDIR) TOPDIR=$(CURDIR) CC_FOR_BUILD=cc -C adk/config conf
EOF
    fi
}

kclause-post-binding-hook-openadk(system, revision, date_prefix=) {
    if [[ $system == openadk ]]; then
        # keep package symbols parser-safe downstream
        sed -i 's/-/_/g; s#/#_#g; s/[.]/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"

        # clean generated fragments before the next checkout
        git reset --hard -q
        git clean -q -dfx
    fi
}

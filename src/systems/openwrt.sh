#!/bin/bash

OPENWRT_URL=https://github.com/openwrt/openwrt

define-system \
    --system openwrt \
    --kconfig-file Config.in \
    --lkc-directory scripts/config \
    --lkc-target torte-config \
    --environment TOPDIR=.,STAGING_DIR=staging_dir,TMP_DIR=tmp,HOSTCC=gcc,CC=gcc,HOST_OS=Linux \
    --sample-branch master

add-openwrt-system() {
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-openwrt
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-openwrt
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-openwrt
    add-system --system openwrt --url "$OPENWRT_URL"
}

add-openwrt-kconfig-tags(from=, to=) {
    add-openwrt-kconfig-revisions "$(openwrt-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

openwrt-tags() {
    git-tags openwrt | grep -E '^v[0-9]+[.][0-9]+[.][0-9]+$'
}

kconfig-post-checkout-hook-openwrt(system, revision) {
    if [[ $system == openwrt ]]; then
        prepare-openwrt-generated-kconfig
    fi
}

kconfig-pre-binding-hook-openwrt(system, revision, lkc_directory=) {
    if [[ $system == openwrt ]]; then
        prepare-openwrt-generated-kconfig
        patch-openwrt-kconfig-host-includes
    fi
}

prepare-openwrt-generated-kconfig() {
    # satisfy the metadata scanner without running build prerequisites
    mkdir -p staging_dir/host/bin tmp/info tmp feeds
    touch staging_dir/host/.prereq-build

    patch-openwrt-scan-awk

    # provide the mkhash interface used by metadata rescans
    if [[ ! -x staging_dir/host/bin/mkhash ]]; then
        cat > staging_dir/host/bin/mkhash <<'EOF'
#!/bin/sh
case "$1" in
    md5) shift; md5sum "$@" ;;
    *) md5sum "$@" ;;
esac
EOF
        chmod +x staging_dir/host/bin/mkhash
    fi

    # prefer the native generator, then fall back to direct metadata scanning
    make prepare-tmpinfo FORCE=1 >/dev/null 2>&1 || true
    if ! openwrt-generated-kconfig-looks-complete; then
        run-openwrt-metadata-scanner
    fi

    write-openwrt-generated-kconfig-fallbacks
    write-openwrt-minimal-lkc-target
}

openwrt-generated-kconfig-looks-complete() {
    [[ -f tmp/.config-package.in && -f tmp/.config-target.in ]] || return 1
    [[ $(wc -l < tmp/.config-package.in) -gt 1000 ]] || return 1
    [[ $(wc -l < tmp/.config-target.in) -gt 1000 ]] || return 1
}

run-openwrt-metadata-scanner() {
    # mirror prepare-tmpinfo without package-manager or build-prereq checks
    mkdir -p tmp/info feeds
    rm -f tmp/.packageinfo tmp/.targetinfo tmp/.config-package.in tmp/.config-target.in

    make -j1 -r -s -f include/scan.mk \
        SCAN_TARGET=packageinfo \
        SCAN_DIR=package \
        SCAN_NAME=package \
        SCAN_DEPTH=5 \
        SCAN_EXTRA= >/dev/null 2>&1 || true
    make -j1 -r -s -f include/scan.mk \
        SCAN_TARGET=targetinfo \
        SCAN_DIR=target/linux \
        SCAN_NAME=target \
        SCAN_DEPTH=3 \
        SCAN_EXTRA= \
        SCAN_MAKEOPTS=TARGET_BUILD=1 >/dev/null 2>&1 || true

    if [[ -f scripts/package-metadata.pl && -f tmp/.packageinfo ]]; then
        scripts/package-metadata.pl config tmp/.packageinfo > tmp/.config-package.in 2>/dev/null || true
    fi
    if [[ -f scripts/target-metadata.pl && -f tmp/.targetinfo ]]; then
        scripts/target-metadata.pl config tmp/.targetinfo > tmp/.config-target.in 2>/dev/null || true
    fi
    if [[ -x scripts/feeds ]]; then
        scripts/feeds feed_config > tmp/.config-feeds.in 2>/dev/null || true
    fi
}

patch-openwrt-scan-awk() {
    # asort needs gawk, but ordering does not affect kconfig semantics
    if [[ -f include/scan.awk ]] && grep -q 'asort' include/scan.awk; then
        cat > include/scan.awk <<'EOF'
BEGIN { FS="/" }
$1 ~ /^feeds/ { FEEDS[$NF]=$0 }
$1 !~ /^feeds/ { PKGS[$NF]=$0 }
END {
	for (pkg in PKGS)
		print PKGS[pkg]
	for (pkg in PKGS)
		delete FEEDS[pkg]
	for (pkg in FEEDS)
		print FEEDS[pkg]
}
EOF
    fi
}

write-openwrt-generated-kconfig-fallbacks() {
    mkdir -p tmp
    [[ -f tmp/.config-package.in ]] || : > tmp/.config-package.in
    [[ -f tmp/.config-target.in ]] || : > tmp/.config-target.in
    [[ -f tmp/.config-feeds.in ]] || : > tmp/.config-feeds.in
}

patch-openwrt-kconfig-host-includes() {
    if [[ -f scripts/config/internal.h ]] \
        && [[ -f scripts/config/Makefile ]] \
        && ! grep -q 'torte: common kconfig objects need the local header dir' scripts/config/Makefile; then
        cat >> scripts/config/Makefile <<'EOF'

# torte: common kconfig objects need the local header dir after conf.c is replaced
KBUILD_HOSTCFLAGS += -I $(src)
EOF
    fi
}

write-openwrt-minimal-lkc-target() {
    if [[ -f Makefile ]] && ! grep -q '^torte-config:' Makefile; then
        cat >> Makefile <<'EOF'

# torte: build only the revision-local kconfig frontend for extractor bindings
.PHONY: torte-config
torte-config:
	$(MAKE) -C scripts/config conf
EOF
    fi
}

kclause-post-binding-hook-openwrt(system, revision, date_prefix=) {
    if [[ $system == openwrt ]]; then
        # keep package and target symbols parser-safe downstream
        sed -i 's/-/_/g; s#/#_#g; s/[.]/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"
    fi
}

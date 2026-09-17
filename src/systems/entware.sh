#!/bin/bash

ENTWARE_URL=https://github.com/Entware/Entware

define-system \
    --system entware \
    --kconfig-file Config.in \
    --lkc-directory scripts/config \
    --lkc-target torte-conf \
    --environment TOPDIR=.,STAGING_DIR=staging_dir,TMP_DIR=tmp,HOSTCC=cc,CC=cc,HOST_OS=Linux \
    --sample-branch master

add-entware-system() {
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-entware
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-entware
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-entware
    add-system --system entware --url "$ENTWARE_URL"
}

kconfig-post-checkout-hook-entware(system, revision) {
    if [[ $system == entware ]]; then
        prepare-entware-generated-kconfig
    fi
}

kconfig-pre-binding-hook-entware(system, revision, lkc_directory=) {
    if [[ $system == entware ]]; then
        prepare-entware-generated-kconfig
        patch-entware-old-lkc
    fi
}

prepare-entware-generated-kconfig() {
    mkdir -p staging_dir/host/bin tmp/info feeds logs
    [[ -e feeds/base ]] || ln -sf ../package feeds/base
    touch staging_dir/host/.prereq-build

    patch-entware-scan-awk
    write-entware-mkhash
    run-entware-metadata-scanner
    write-entware-generated-kconfig-fallbacks
    normalize-entware-kconfig-symbols
    write-entware-minimal-lkc-target
}

patch-entware-scan-awk() {
    # old scanner uses gawk asort, but order does not affect kconfig semantics
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

write-entware-mkhash() {
    if [[ ! -x staging_dir/host/bin/mkhash ]]; then
        cat > staging_dir/host/bin/mkhash <<'EOF'
#!/bin/sh
case "$1" in
    md5) shift ;;
esac
if command -v md5sum >/dev/null 2>&1; then
    md5sum "$@"
else
    md5 -r "$@"
fi
EOF
        chmod +x staging_dir/host/bin/mkhash
    fi
}

run-entware-metadata-scanner() {
    local topdir
    topdir=$(pwd -P)
    rm -f tmp/.packageinfo tmp/.targetinfo tmp/.config-package.in tmp/.config-target.in tmp/.config-feeds.in

    TOPDIR="$topdir" PATH="$topdir/staging_dir/host/bin:$PATH" \
        make -j1 -r -s -f include/scan.mk \
        SCAN_TARGET=packageinfo \
        SCAN_DIR=package \
        SCAN_NAME=package \
        SCAN_DEPS="$topdir/include/package*.mk" \
        SCAN_DEPTH=5 \
        SCAN_EXTRA= >/dev/null 2>&1 || true

    TOPDIR="$topdir" PATH="$topdir/staging_dir/host/bin:$PATH" \
        make -j1 -r -s -f include/scan.mk \
        SCAN_TARGET=targetinfo \
        SCAN_DIR=target/linux \
        SCAN_NAME=target \
        SCAN_DEPS="image/Makefile profiles/*.mk $topdir/include/kernel*.mk $topdir/include/target.mk" \
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

write-entware-generated-kconfig-fallbacks() {
    mkdir -p tmp
    [[ -f tmp/.config-package.in ]] || : > tmp/.config-package.in
    [[ -f tmp/.config-target.in ]] || : > tmp/.config-target.in
    [[ -f tmp/.config-feeds.in ]] || : > tmp/.config-feeds.in
}

normalize-entware-kconfig-symbols() {
    # old metadata can put punctuation in symbol names
    # normalize symbol-bearing lines but leave source paths alone
    find . -path './.git' -prune -o -type f \( -name Config.in -o -name Kconfig \) -print | while read -r kconfig; do
        normalize-entware-kconfig-symbol-file "$kconfig"
    done

    local generated
    for generated in tmp/.config-package.in tmp/.config-target.in tmp/.config-feeds.in; do
        [[ -f $generated ]] || continue
        normalize-entware-kconfig-symbol-file "$generated"
    done
}

normalize-entware-kconfig-symbol-file(file) {
    local temporary
    temporary="$file.torte-normalized"

    # use awk+mv because bsd sed and gnu sed differ on in-place edits
    # also clean up malformed dependency tails from old metadata generators
    awk '
        function normalize(line) {
            gsub(/\|\|/, " || ", line)
            gsub(/&&/, " \\&\\& ", line)
            gsub(/PACKAGE_PACKAGE_/, "PACKAGE_", line)
            sub(/[[:space:]]*(\|\||&&)[[:space:]]*$/, "", line)
            gsub(/-/, "_", line)
            gsub(/\//, "_", line)
            gsub(/[.]/, "_", line)
            return line
        }
        /^[[:space:]]*(config|menuconfig|default|depends[[:space:]]+on|select|imply|range|visible[[:space:]]+if|if)([[:space:]]|$)/ {
            print normalize($0)
            next
        }
        /^[[:space:]]*(PACKAGE|DEFAULT|TARGET|BUSYBOX|OPENVPN|MBEDTLS|OPENSSL|LIBCURL|WOLFSSL|KERNEL|CONFIG)_[A-Za-z0-9_.\/-]*/ {
            print normalize($0)
            next
        }
        { print }
    ' "$file" > "$temporary" && mv "$temporary" "$file"
    rm -f "$temporary"
}

patch-entware-old-lkc() {
    [[ -d scripts/config ]] || return
    (
        cd scripts/config || exit

        # materialize shipped parser files for old openwrt-era lkc trees
        [[ -s zconf.tab.c || ! -f zconf.tab.c_shipped ]] || cp zconf.tab.c_shipped zconf.tab.c
        [[ -s zconf.hash.c || ! -f zconf.hash.c_shipped ]] || cp zconf.hash.c_shipped zconf.hash.c
        [[ -s zconf.lex.c || ! -f zconf.lex.c_shipped ]] || cp zconf.lex.c_shipped zconf.lex.c
    )
}

write-entware-minimal-lkc-target() {
    if [[ -f Makefile ]] && ! grep -q '^torte-conf:' Makefile; then
        cat >> Makefile <<'EOF'

# torte: build only entware's revision-local kconfig frontend
.PHONY: torte-conf
torte-conf:
	$(MAKE) --no-print-directory -C scripts/config conf CC=cc
EOF
    fi
}

kclause-post-binding-hook-entware(system, revision, date_prefix=) {
    if [[ $system == entware ]]; then
        # keep package symbols parser-safe downstream
        sed -i 's/-/_/g; s#/#_#g; s/[.]/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"
    fi
}

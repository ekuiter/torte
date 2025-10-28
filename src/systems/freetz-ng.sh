#!/bin/bash

FREETZ_NG_URL=https://github.com/Freetz-NG/freetz-ng

# like BusyBox, Freetz-NG generates parts of its feature model (with https://github.com/Freetz-NG/freetz-ng/blob/master/tools/genin)
# this is no issue as long as we don't aim to analyze every single commit that touches the feature model
# (for BusyBox, we enable this with generate-busybox-models, and a similar approach could probably be used here)

# determine the correct KConfig file for Freetz-NG at the given revision
find-freetz-ng-kconfig-file(revision) {
    if git -C "$(input-directory)/freetz-ng" cat-file -e "$revision:Config.in" 2>/dev/null; then
        echo Config.in
    else
        echo config/Config.in
    fi
}

# determine the correct LKC directory for Freetz-NG at the given revision
find-freetz-ng-lkc-directory(revision) {
    if git -C "$(input-directory)/freetz-ng" cat-file -e "$revision:tools/config/conf.c" 2>/dev/null; then
        echo tools/config
    else
        echo source/host-tools/kconfig*/scripts/kconfig
    fi
}

add-freetz-ng-system() {
    add-system --system freetz-ng --url "$FREETZ_NG_URL"
}

add-freetz-ng-kconfig(revision) {
    add-freetz-ng-system
    add-revision --system freetz-ng --revision "$revision"
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-freetz-ng
    add-kconfig \
        --system freetz-ng \
        --revision "$revision" \
        --kconfig-file "$(find-freetz-ng-kconfig-file "$revision")" \
        --lkc-directory "$(find-freetz-ng-lkc-directory "$revision")"
}

kconfig-post-checkout-hook-freetz-ng(system, revision) {
    if [[ $system == freetz-ng ]]; then
        if [[ -f Makefile ]]; then
            # we don't care about permissions or missing dependencies, we just want to compile our binding
            sed -i 's/.*Running makefile as root is prohibited!.*//g' Makefile
            sed -i 's/.*prerequisites are missing!.*//g' Makefile
            sed -i 's/.*error Please re-run.*//g' Makefile
            sed -i 's/.*empty directory root\/sys is missing!.*//g' Makefile
            sed -i 's/.*File permissions or links are wrong!.*//g' Makefile
            # in revision dd5227ed5, this dependency on deps_config_cache leads to an infinite loop in the makefile
            # as it does not affect the extraction, we remove it here
            sed -i 's/\$(deps_config_cache)$//g' Makefile
        fi
        if [[ -f tools/make/kconfig.mk ]]; then
            # in revision 0b9a5803e, the URL to download LKC is outdated and placed in the wrong directory
            sed -i 's#http://git.kernel.org/?p=linux/kernel/git/torvalds/linux.git.*$#https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot/linux-\$(KCONFIG_VERSION).tar.gz#g' tools/make/kconfig.mk
            sed -i 's#/scripts##g' tools/make/kconfig.mk
        fi
        # since 2012, freetz-ng has a rather advanced mechanism that downloads LKC during the first call to "make config" and automatically patches it afterwards
        # to be able to correctly locate the LKC implementation in the source tree, we need to run "make config" once here before compiling the binding
        # it is important that this is not a pre-binding hook, because that hook already assumes that the location of LKC is known
        # see https://github.com/Freetz-NG/freetz-ng/tree/master/make/host-tools/kconfig-host
        # should the LKC download fail for some reason in the future, a mirror for several versions is available here: https://github.com/Freetz-NG/dl-mirror
        yes "" | make config 2>&1 || true
        # force recompilation of the binding later on in compile-lkc-binding for recent versions of freetz-ng ...
        make clean 2>&1 || true
        # ... and for older versions
        make -C tools/config clean 2>&1 || true
    fi
}

add-freetz-ng-kconfig-revisions(revisions=) {
    add-freetz-ng-system
    if [[ -z $revisions ]]; then
        return
    fi
    while read -r revision; do
        add-freetz-ng-kconfig --revision "$revision"
    done < <(printf '%s\n' "$revisions")
}

add-freetz-ng-kconfig-sample(interval) {
    add-freetz-ng-kconfig-revisions "$(memoize-global git-sample-revisions freetz-ng "$interval" master)"
}

add-freetz-ng-kconfig-history(interval_name=yearly) {
    add-freetz-ng-kconfig-sample --interval "$(interval "$interval_name")"
}
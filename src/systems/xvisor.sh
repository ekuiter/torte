#!/bin/bash

XVISOR_URL=https://github.com/xvisor/xvisor

define-system \
    --system xvisor \
    --kconfig-file openconf.cfg \
    --lkc-directory tools/openconf \
    --lkc-target torte-config \
    --environment OPENCONF_INPUT=openconf.cfg,OPENCONF_SRCTREE=.,OPENCONF_TMPDIR=build/openconf,CONFIG_SHELL=/bin/bash,HOSTCC=gcc,HOST_CC=gcc \
    --sample-branch master

add-xvisor-system() {
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-xvisor
    add-system --system xvisor --url "$XVISOR_URL"
}

add-xvisor-kconfig-tags(from=, to=) {
    add-xvisor-kconfig-revisions "$(git-tags xvisor | start-at-revision "$from" | stop-at-revision "$to")"
}

kconfig-pre-binding-hook-xvisor(system, revision, lkc_directory=) {
    if [[ $system == xvisor ]]; then
        [[ -d tools/openconf ]] || return
        write-xvisor-minimal-lkc-target
        patch-xvisor-kextractor-prefix

        # create missing header file before conf.c is replaced
        (
            cd tools/openconf || exit
            if [[ ! -f lkc.h ]]; then
                cat > lkc.h <<'EOF'
/* torte: provide the lkc.h name expected by generic bindings
*/
#ifndef LKC_H
#define LKC_H
#ifdef LKC_DIRECT_LINK
#define OPENCONF_DIRECT_LINK
#endif
#include "openconf.h"
#endif
EOF
            fi
        )
    fi
}

patch-xvisor-kextractor-prefix() {
    # xvisor already declares symbols as CONFIG_FOO
    # do not let kextractor emit CONFIG_CONFIG_FOO
    perl -pi -e 's/static char \*config_prefix = "CONFIG_";/static char *config_prefix = "";/' tools/openconf/conf.c
}

write-xvisor-minimal-lkc-target() {
    if ! grep -q '^torte-config:' Makefile; then
        cat >> Makefile <<'EOF'

# torte: build only the replacement openconf frontend
.PHONY: torte-config
torte-config:
	$(MAKE) -C tools/openconf conf
EOF
    fi
}

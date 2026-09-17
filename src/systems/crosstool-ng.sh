#!/bin/bash

CROSSTOOL_NG_URL=https://github.com/crosstool-ng/crosstool-ng

define-system \
    --system crosstool-ng \
    --kconfig-file config/config.in \
    --lkc-directory kconfig \
    --environment "CT_VERSION=0,CT_CONFIG_VERSION_CURRENT=4,CT_VCHECK=,srctree=." \
    --sample-branch master

add-crosstool-ng-system() {
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-crosstool-ng
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-crosstool-ng
    add-system --system crosstool-ng --url "$CROSSTOOL_NG_URL"
}

add-crosstool-ng-kconfig-tags(from=, to=) {
    add-crosstool-ng-kconfig-revisions "$(crosstool-ng-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

crosstool-ng-tags() {
    git-tags crosstool-ng | grep -E '^crosstool-ng-[0-9]+[.][0-9]+[.][0-9]+$'
}

kconfig-post-checkout-hook-crosstool-ng(system, revision) {
    if [[ $system == crosstool-ng ]]; then
        prepare-crosstool-ng-generated-kconfig
    fi
}

prepare-crosstool-ng-generated-kconfig() {
    # bootstrap writes the generated kconfig fragments before autoreconf
    if [[ -x bootstrap ]] && [[ ! -d config/gen || ! -d config/versions ]]; then
        QUIET=1 ./bootstrap >/dev/null 2>&1 || true
    fi

    # old release-style trees can use their checked-in configure script
    if [[ -x configure && ! -f Makefile ]]; then
        ./configure --enable-local >/dev/null 2>&1 || true
    fi

    # middle-era trees generate config.gen through config/config.mk
    if [[ -f config/config.mk && ! -d config.gen ]]; then
        # old helper assumes gnu sed -s
        if [[ -f scripts/gen_in_frags.sh ]]; then
            sed -i 's/ -s//g' scripts/gen_in_frags.sh
        fi
        make -f config/config.mk config_files \
            CT_LIB_DIR=. \
            CT_ECHO=true \
            SILENT= \
            sed=sed \
            sed_r="sed -E" \
            grep=grep >/dev/null 2>&1 || true
    fi

    write-crosstool-ng-legacy-config-gen
    normalize-crosstool-ng-kconfig-sources
    write-crosstool-ng-generated-lkc-sources
    write-crosstool-ng-configure-kconfig
    write-crosstool-ng-minimal-makefiles
}

write-crosstool-ng-legacy-config-gen() {
    # fill missing config.gen aggregators for older snapshots
    local generated_fragment base suffix source_dir
    grep -RhoE 'source[[:space:]]+"?config\.gen/[^"[:space:]]+' config 2>/dev/null \
        | sed -E 's/.*config\.gen\///' \
        | sort -u \
        | while read -r generated_fragment; do
            [[ -n $generated_fragment && ! -f config.gen/$generated_fragment ]] || continue
            base=${generated_fragment%.in}
            suffix=.in
            if [[ $generated_fragment == *.in.2 ]]; then
                base=${generated_fragment%.in.2}
                suffix=.in.2
            fi
            source_dir=config/$base
            [[ -d $source_dir ]] || continue

            mkdir -p config.gen
            {
                for source_fragment in "$source_dir"/*"$suffix"; do
                    [[ -f $source_fragment ]] && printf 'source "%s"\n' "$source_fragment"
                done
            } > "config.gen/$generated_fragment"
        done
}

normalize-crosstool-ng-kconfig-sources() {
    # normalize old unquoted sources and named choices for kclause
    for source_dir in config config.gen; do
        [[ -d $source_dir ]] || continue
        find "$source_dir" -type f \( -name '*.in' -o -name '*.in.2' \) \
            -exec sed -i -E 's/^([[:space:]]*)source[[:space:]]+([^"[:space:]][^[:space:]]*)[[:space:]]*$/\1source "\2"/; s/^([[:space:]]*)choice[[:space:]]+[A-Za-z0-9_]+[[:space:]]*$/\1choice/' {} \;
    done
}

write-crosstool-ng-generated-lkc-sources() {
    # materialize old generated parser files before compiling the binding
    [[ -d kconfig ]] || return 0
    pushd kconfig >/dev/null || return 0

    if [[ ! -s zconf.tab.c && -f zconf.tab.c_shipped ]]; then
        cp zconf.tab.c_shipped zconf.tab.c
    elif [[ ! -s zconf.tab.c && -f zconf.y ]] && command -v bison >/dev/null 2>&1; then
        bison -l -b zconf -p zconf zconf.y >/dev/null 2>&1 || true
    fi

    local zconf_lexer_file=lex.zconf.c
    if grep -q '#include "zconf\.lex\.c"' zconf.y 2>/dev/null; then
        zconf_lexer_file=zconf.lex.c
    fi

    if [[ ! -s $zconf_lexer_file && -f ${zconf_lexer_file}_shipped ]]; then
        cp "${zconf_lexer_file}_shipped" "$zconf_lexer_file"
    elif [[ ! -s $zconf_lexer_file && $zconf_lexer_file == lex.zconf.c && -f lex.zconf.c_shipped ]]; then
        cp lex.zconf.c_shipped lex.zconf.c
    elif [[ ! -s $zconf_lexer_file && -f zconf.l ]] && command -v flex >/dev/null 2>&1; then
        flex -L -Pzconf -o"$zconf_lexer_file" zconf.l >/dev/null 2>&1 || true
    fi

    if [[ ! -s zconf.hash.c && -f zconf.hash.c_shipped ]]; then
        cp zconf.hash.c_shipped zconf.hash.c
    elif [[ ! -s zconf.hash.c && -f zconf.gperf ]] && command -v gperf >/dev/null 2>&1; then
        gperf < zconf.gperf > zconf.hash.c 2>/dev/null || true
    fi
    if [[ ! -s zconf.hash.c && -f zconf.gperf ]]; then
        write-crosstool-ng-linear-zconf-hash
    fi

    # patch old gperf output for newer compilers
    if [[ -s zconf.hash.c ]]; then
        sed -i 's/^__inline$/static __inline/' zconf.hash.c
        sed -i '/^static unsigned int$/{N;/kconf_id_hash/s/^static //;}' zconf.hash.c
    fi

    popd >/dev/null
}

write-crosstool-ng-linear-zconf-hash() {
    # fallback for containers without gperf
    awk '
        function trim(s) {
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            return s
        }
        function c_escape(s) {
            gsub(/["\\]/, "\\\\&", s)
            return s
        }
        /^%%$/ {
            section++
            next
        }
        section == 1 && NF {
            split($0, fields, ",")
            name = trim(fields[1])
            token = trim(fields[2])
            flags = trim(fields[3])
            stype = trim(fields[4])
            if (name == "" || token == "" || flags == "")
                next
            if (stype == "")
                stype = "S_UNKNOWN"
            names[++count] = name
            offsets[count] = offset
            tokens[count] = token
            flagses[count] = flags
            stypes[count] = stype
            offset += length(name) + 1
        }
        END {
            print "#include <string.h>"
            print "static const char kconf_id_strings[] ="
            for (i = 1; i <= count; i++)
                printf "\t\"%s\\0\"\n", c_escape(names[i])
            print "\t;"
            print "static struct kconf_id kconf_id_table[] = {"
            for (i = 1; i <= count; i++)
                printf "\t{ %d, %s, %s, %s },\n", offsets[i], tokens[i], flagses[i], stypes[i]
            print "};"
            print "static struct kconf_id *kconf_id_lookup(register const char *str, register unsigned int len)"
            print "{"
            print "\tunsigned int i;"
            print "\tfor (i = 0; i < sizeof(kconf_id_table) / sizeof(kconf_id_table[0]); i++) {"
            print "\t\tconst char *name = kconf_id_strings + kconf_id_table[i].name;"
            print "\t\tif (strlen(name) == len && memcmp(name, str, len) == 0)"
            print "\t\t\treturn &kconf_id_table[i];"
            print "\t}"
            print "\treturn 0;"
            print "}"
        }
    ' zconf.gperf > zconf.hash.c
}

write-crosstool-ng-configure-kconfig() {
    # make host-tool probe symbols deterministic
    if [[ ! -s config/configure.in && -f config/configure.in.in ]]; then
        sed -E 's/@KCONFIG_[^@]+@/    def_bool y/' config/configure.in.in > config/configure.in
    elif grep -q '@KCONFIG_' config/configure.in 2>/dev/null; then
        sed -i -E 's/@KCONFIG_[^@]+@/    def_bool y/' config/configure.in
    elif grep -q 'source "config/configure.in"' config/config.in 2>/dev/null && [[ ! -f config/configure.in ]]; then
        mkdir -p config
        : > config/configure.in
    fi
}

write-crosstool-ng-minimal-makefiles() {
    cat > Makefile <<'EOF'
# torte: build only kconfig/conf
.PHONY: config
config:
	$(MAKE) -C kconfig conf
EOF

    if [[ -f kconfig/parser.y && -f kconfig/lexer.l ]]; then
        cat > kconfig/Makefile <<'EOF'
# torte: fallback for makefile.am-only releases
CFLAGS += -include ../config.h -DCONFIG_=\"CT_\" -DKBUILD_NO_NLS -I.

conf: conf.o confdata.o expr.o symbol.o preprocess.o util.o parser.tab.o lexer.lex.o
	$(CC) -o $@ $^

parser.tab.c parser.tab.h: parser.y
	bison -t -l -o parser.tab.c --defines=parser.tab.h parser.y

lexer.lex.c: lexer.l parser.tab.h
	flex -L -o lexer.lex.c lexer.l

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
EOF
    elif [[ -f kconfig/kconf_id.c && -f kconfig/zconf.y ]]; then
        cat > kconfig/Makefile <<'EOF'
# torte: middle-era conf-only path without autotools
CFLAGS += -include ../config.h -DCONFIG_=\"CT_\" -DKBUILD_NO_NLS -I.

conf: zconf.o conf.o
	$(CC) -o $@ $^

zconf.c: zconf.y
	bison -t -l -b zconf -p zconf -o$@ $<

zconf.lex.c: zconf.l
	flex -L -Pzconf -o$@ $<

zconf.o: zconf.c zconf.lex.c kconf_id.c
	$(CC) $(CFLAGS) -c -o $@ zconf.c

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
EOF
    elif [[ -f kconfig/zconf.y || -f kconfig/zconf.tab.c || -f kconfig/zconf.tab.c_shipped ]]; then
        local zconf_lexer_file=lex.zconf.c
        if grep -q '#include "zconf\.lex\.c"' kconfig/zconf.y 2>/dev/null; then
            zconf_lexer_file=zconf.lex.c
        fi
        cat > kconfig/Makefile <<'EOF'
# torte: old-lkc conf-only build with shipped parser fallbacks
ZCONF_LEX ?= lex.zconf.c
CFLAGS += -DCONFIG_=\"CT_\" -DPACKAGE=\"crosstool-NG\" -DKBUILD_NO_NLS -include stddef.h -I.

conf: zconf.tab.o conf.o
	$(CC) -o $@ $^

zconf.tab.c:
	if [ -f zconf.tab.c_shipped ]; then cp zconf.tab.c_shipped $@; else bison -l -b zconf -p zconf zconf.y; fi

zconf.hash.c:
	if [ -f zconf.hash.c_shipped ]; then cp zconf.hash.c_shipped $@; else gperf < zconf.gperf > $@; fi
	sed -i 's/^__inline$$/static __inline/' $@
	sed -i '/^static unsigned int$$/{N;/kconf_id_hash/s/^static //;}' $@

$(ZCONF_LEX):
	if [ -f $(ZCONF_LEX)_shipped ]; then cp $(ZCONF_LEX)_shipped $@; elif [ "$(ZCONF_LEX)" = "lex.zconf.c" ] && [ -f lex.zconf.c_shipped ]; then cp lex.zconf.c_shipped $@; else flex -L -Pzconf -o$@ zconf.l; fi

zconf.tab.o: zconf.tab.c zconf.hash.c $(ZCONF_LEX)
	$(CC) $(CFLAGS) -c -o $@ zconf.tab.c

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
EOF
        sed -i "s/^ZCONF_LEX ?=.*/ZCONF_LEX ?= $zconf_lexer_file/" kconfig/Makefile
    fi

    [[ -f config.h ]] || : > config.h
    return 0
}

kconfig-pre-binding-hook-crosstool-ng(system, revision, lkc_directory=) {
    if [[ $system == crosstool-ng ]]; then
        prepare-crosstool-ng-generated-kconfig

        # expose the newer choice representation to the binding
        grep -qrnw "$lkc_directory" --exclude=conf.c -e sym_get_choice_prop && echo HAS_sym_get_choice_prop
    fi
}

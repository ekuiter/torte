#!/bin/bash

add-uclibc-ng-kconfig-history(from=, to=) {
    # environment variable ARCH, VERSION undefined
    add-system --system uclibc-ng --url https://github.com/wbx-github/uclibc-ng
    for revision in $(git-tag-revisions uclibc-ng | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc-ng --revision "$revision"
        add-kconfig \
            --system uclibc-ng \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --lkc-directory extra/config
    done
}

read-uclibc-ng-configs() {
    add-revision(system, revision) {
        if [[ $system == uclibc-ng ]]; then
            log "read-uclibc-ng-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/uclibc-ng ]]; then
                error "uClibc-ng has not been cloned yet. Please prepend a stage that clones uClibc-ng."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig_file,config >> "$configs"
            echo system,revision,kconfig_file,config,type >> "$config_types"

            uclibc-ng-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            uclibc-ng-config-types "$revision" >> "$config_types"
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

uclibc-ng-configs(revision) {
    git -C "$(input-directory)/uclibc-ng" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "uclibc-ng", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

uclibc-ng-config-types(revision) {
    git -C "$(input-directory)/uclibc-ng" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config.in[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config.in[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "uclibc-ng", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


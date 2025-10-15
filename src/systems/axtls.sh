#!/bin/bash

add-axtls-kconfig-history(from=, to=) {
    # use a frozen Git copy of the original SVN repository
    add-system --system axtls --url https://github.com/ekuiter/axTLS
    for revision in $(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system axtls --revision "$revision"
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --lkc-directory config/scripts/config
    done
}

read-axtls-configs() {
    add-revision(system, revision) {
        if [[ $system == axtls ]]; then
            log "read-axtls-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/axtls ]]; then
                error "axTLS has not been cloned yet. Please prepend a stage that clones axTLS."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig_file,config >> "$configs"
            echo system,revision,kconfig_file,config,type >> "$config_types"

            axtls-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            axtls-config-types "$revision" >> "$config_types"
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

axtls-configs(revision) {
    git -C "$(input-directory)/axtls" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "axtls", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

axtls-config-types(revision) {
    git -C "$(input-directory)/axtls" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "axtls", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


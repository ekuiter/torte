#!/bin/bash

add-freetz-ng-kconfig(revision) {
    add-linux-kconfig-binding --revision v6.7
    add-system --system freetz-ng --url https://github.com/Freetz-NG/freetz-ng
    add-hook-step kconfig-post-checkout-hook freetz-ng "$(to-lambda kconfig-post-checkout-hook-freetz-ng)"
    add-revision --system freetz-ng --revision "$revision"
    add-kconfig-model \
        --system freetz-ng \
        --revision "$revision" \
        --kconfig-file config/Config.in \
        --kconfig-binding-file "$(linux-kconfig-binding-file v6.7)"
}

kconfig-post-checkout-hook-freetz-ng(system, revision) {
    if [[ $system == freetz-ng ]]; then
        # ugly hack because freetz-ng is weird
        mkdir -p make/pkgs
        touch make/Config.in.generated make/external.in.generated make/pkgs/external.in.generated make/pkgs/Config.in.generated config/custom.in
    fi
}

read-freetz-ng-configs() {
    add-revision(system, revision) {
        if [[ $system == freetz-ng ]]; then
            log "read-freetz-ng-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/freetz-ng ]]; then
                error "Freetz-NG has not been cloned yet. Please prepend a stage that clones Freetz-NG."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig-file,config >> "$configs"
            echo system,revision,kconfig-file,config,type >> "$config_types"

            freetz-ng-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            freetz-ng-config-types "$revision" >> "$config_types"
            if [[ ! -f $(output-file types.csv) ]]; then
                join-tables "$configs" "$config_types" | head -n1 > "$(output-file types.csv)"
            fi
            join-tables "$configs" "$config_types" | tail -n+2 >> "$(output-file types.csv)"

            log "" "$(echo-done)"
            rm-safe "$configs" "$config_types"
        fi
    }

    echo system,revision,kconfig-file,config > "$(output-csv)"
    experiment-systems
}

freetz-ng-configs(revision) {
    git -C "$(input-directory)/freetz-ng" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "freetz-ng", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

freetz-ng-config-types(revision) {
    git -C "$(input-directory)/freetz-ng" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "freetz-ng", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


#!/bin/bash

add-embtoolkit-kconfig-history(from=, to=) {
    add-system --system embtoolkit --url https://github.com/ndmsystems/embtoolkit # this seems not to be entirely up-to-date, todo: maybe create a new more up-to-date repository?
    add-hook-step kclause-post-binding-hook embtoolkit "$(to-lambda kclause-post-binding-hook-embtoolkit)"
    for revision in $(git-tag-revisions embtoolkit | exclude-revision rc | grep -v -e '-.*-' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system embtoolkit --revision "$revision"
        add-kconfig \
            --system embtoolkit \
            --revision "$revision" \
            --kconfig-file Kconfig \
            --lkc-directory scripts/kconfig \
            --lkc-target olddefconfig
    done
}

kclause-post-binding-hook-embtoolkit(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
    fi
}

read-embtoolkit-configs() {
    add-revision(system, revision) {
        if [[ $system == embtoolkit ]]; then
            log "read-embtoolkit-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/embtoolkit ]]; then
                error "embtoolkit has not been cloned yet. Please prepend a stage that clones embtoolkit."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig_file,config >> "$configs"
            echo system,revision,kconfig_file,config,type >> "$config_types"

            embtoolkit-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            embtoolkit-config-types "$revision" >> "$config_types"
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

embtoolkit-configs(revision) {
    git -C "$(input-directory)/embtoolkit" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Kconfig*' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "embtoolkit", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}


embtoolkit-config-types(revision) {
    git -C "$(input-directory)/embtoolkit" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Kconfig*' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Kconfig[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Kconfig[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "embtoolkit", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


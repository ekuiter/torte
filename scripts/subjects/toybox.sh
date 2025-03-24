#!/bin/bash

add-toybox-kconfig-history(from=, to=) {
    # do not use this toybox model, it is probably incorrect
    add-system --system toybox --url https://github.com/landley/toybox
    add-hook-step kconfig-post-checkout-hook toybox "$(to-lambda kconfig-post-checkout-hook-toybox)"
    add-linux-kconfig-binding --revision v6.7
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig-model \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v6.7)"
    done
}

kconfig-post-checkout-hook-toybox(system, revision) {
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
}

read-toybox-configs() {
    add-revision(system, revision) {
        if [[ $system == toybox ]]; then
            log "read-toybox-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/toybox ]]; then
                error "Toybox has not been cloned yet. Please prepend a stage that clones Toybox."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig-file,config >> "$configs"
            echo system,revision,kconfig-file,config,type >> "$config_types"

            toybox-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            toybox-config-types "$revision" >> "$config_types"
            if [[ ! -f $(output-file types.csv) ]]; then
                join-tables "$configs" "$config_types" | head -n1 > "$(output-file types.csv)"
            fi
            join-tables "$configs" "$config_types" | tail -n+2 >> "$(output-file types.csv)"

            log "" "$(echo-done)"
            rm-safe "$configs" "$config_types"
        fi
    }

    echo system,revision,kconfig-file,config > "$(output-csv)"
    experiment-subjects
}

toybox-configs(revision) {
    git -C "$(input-directory)/toybox" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "toybox", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

toybox-config-types(revision) {
    git -C "$(input-directory)/toybox" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "toybox", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


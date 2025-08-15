#!/bin/bash

add-buildroot-kconfig-history(from=, to=) {
    export BR2_EXTERNAL=support/dummy-external
    export BUILD_DIR=buildroot
    export BASE_DIR=buildroot
    add-system --system buildroot --url https://github.com/buildroot/buildroot
    add-linux-kconfig-binding --revision v6.7
    add-hook-step kconfig-post-checkout-hook buildroot "$(to-lambda kconfig-post-checkout-hook-buildroot)"
    for revision in $(git-tag-revisions buildroot | exclude-revision rc _ 'settings-.*' '\..*\.' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system buildroot --revision "$revision"
        add-kconfig-model \
            --system buildroot \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v6.7)"
    done
}

kconfig-post-checkout-hook-buildroot(system, revision) {
    if [[ $system == buildroot ]]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains \
            .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus \
            .br2-external.in.skeleton .br2-external.in.init
        # ignore generated Kconfig files in buildroot
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \;
    fi
}

read-buildroot-configs() {
    add-revision(system, revision) {
        if [[ $system == buildroot ]]; then
            log "read-buildroot-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/buildroot ]]; then
                error "Buildroot has not been cloned yet. Please prepend a stage that clones Buildroot."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig_file,config >> "$configs"
            echo system,revision,kconfig_file,config,type >> "$config_types"

            buildroot-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            buildroot-config-types "$revision" >> "$config_types"
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

buildroot-configs(revision) {
    git -C "$(input-directory)/buildroot" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "buildroot", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}

buildroot-config-types(revision) {
    git -C "$(input-directory)/buildroot" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config.in' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "buildroot", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


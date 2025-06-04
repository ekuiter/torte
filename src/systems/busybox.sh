#!/bin/bash

add-busybox-kconfig-history(from=, to=) {
    add-system --system busybox --url https://github.com/mirror/busybox
    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

add-busybox-kconfig-history-full() {
    add-system --system busybox --url https://github.com/mirror/busybox
    for revision in $(git -C "$(input-directory)/busybox-models" log master --format="%h" | tac); do
        local original_revision
        original_revision=$(git -C "$(input-directory)/busybox-models" rev-list --max-count=1 --format=%B "$revision" | sed '/^commit [0-9a-f]\{40\}$/d')
        add-revision --system busybox-models --revision "${revision}[$original_revision]"
        add-kconfig \
            --system busybox-models \
            --revision "${revision}[$original_revision]" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

generate-busybox-models() {
    git-checkout master "$(input-directory)/busybox" > /dev/null
    git -C "$(output-directory)" init -q
    echo "*.log" >> "$(output-directory)/.gitignore"
    echo "*.err" >> "$(output-directory)/.gitignore"
    local i n
    i=0
    n=$(git -C "$(input-directory)/busybox" log --format="%h" | wc -l)
    git -C "$(input-directory)/busybox" log --format="%h" | tac | while read -r revision; do
        ((i+=1))
        local timestamp
        timestamp=$(git-timestamp busybox "$revision")
        local dir
        dir=$(output-directory)
        rm -rf "${dir:?}/*"
        git-checkout "$revision" "$(input-directory)/busybox" > /dev/null
        if [[ -f "$(input-directory)/busybox/scripts/gen_build_files.sh" ]]; then
            chmod +x "$(input-directory)/busybox/scripts/gen_build_files.sh"
            make -C "$(input-directory)/busybox" gen_build_files >/dev/null 2>&1 || true
        fi
        (cd "$(input-directory)/busybox" || exit; find . -type f -name "*Config.in" -exec cp --parents {} "$(output-directory)" \;)
        mkdir -p "$(output-directory)/scripts/"
        cp -R "$(input-directory)/busybox/scripts/"* "$(output-directory)/scripts/" 2>/dev/null || true
        cp "$(input-directory)/busybox/Makefile"* "$(output-directory)" 2>/dev/null || true
        cp "$(input-directory)/busybox/Rules.mak" "$(output-directory)" 2>/dev/null || true
        git -C "$(output-directory)" add -A
        if [[ $i -eq 1 ]] || ! git -C "$(output-directory)" diff --staged --exit-code '*Config.in' >/dev/null 2>&1; then
            log "[$i/$n] $revision"
            log "" "$(echo-progress gen)"
            GIT_COMMITTER_DATE=$timestamp git -C "$(output-directory)" commit -q -m "$revision" --date "$timestamp" >/dev/null || true
            log "" "$(echo-done)"
        fi
    done
}

read-busybox-configs() {
    add-revision(system, revision) {
        if [[ $system == busybox ]]; then
            log "read-busybox-configs: $system@$revision" "$(echo-progress read)"
            if grep -q "^$system,$revision," "$(output-csv)"; then
                log "" "$(echo-skip)"
                return
            fi
            if [[ ! -d $(input-directory)/busybox ]]; then
                error "BusyBox has not been cloned yet. Please prepend a stage that clones BusyBox."
            fi
            
            local configs config_types
            configs=$(mktemp)
            config_types=$(mktemp)

            echo system,revision,kconfig-file,config >> "$configs"
            echo system,revision,kconfig-file,config,type >> "$config_types"

            busybox-configs "$revision" >> "$configs"
            tail -n+2 < "$configs" >> "$(output-csv)"

            busybox-config-types "$revision" >> "$config_types"
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

busybox-configs(revision) {
    git -C "$(input-directory)/busybox" grep -E $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | awk -F: $'{OFS=","; gsub("^[ \t]*(menu)?config[ \t]+", "", $3); gsub("#.*", "", $3); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print "busybox", $1, $2, $3}' \
        | grep -E ',.*,.*,[0-9a-zA-Z_]+$' \
        | sort | uniq
}



busybox-config-types(revision) {
    # similar to linux-configs, reads all configuration options, but also tries to read their types from the succeeding line
    # note that this is less accurate than linux-configs due to the complexity of the regular expressions
    # also, this does not exclude the architecture um as done in other functions
    git -C "$(input-directory)/busybox" grep -E -A1 $'^[ \t]*(menu)?config[ \t]+[0-9a-zA-Z_]+' "$revision" -- '**/*Config*' \
        | perl -pe 's/[ \t]*(menu)?config[ \t]+([0-9a-zA-Z_]+).*/$2/' \
        | perl -pe 's/\n/&&&/g' \
        | perl -pe 's/&&&--&&&/\n/g' \
        | perl -pe 's/&&&[^:&]*?:[^:&]*?Config[^:&]*?-/&&&/g' \
        | perl -pe 's/&&&([^:&]*?:[^:&]*?Config[^:&]*?:)/&&&\n$1/g' \
        | perl -pe 's/&&&/:/g' \
        | awk -F: $'{OFS=","; gsub(".*bool.*", "bool", $4); gsub(".*tristate.*", "tristate", $4); gsub(".*string.*", "string", $4); gsub(".*int.*", "int", $4); gsub(".*hex.*", "hex", $4); print "busybox", $1, $2, $3, $4}' \
        | grep -E ',(bool|tristate|string|int|hex)$' \
        | sort | uniq
}


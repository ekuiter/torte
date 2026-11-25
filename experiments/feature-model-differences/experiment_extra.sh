#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# compare BusyBox releases with additional human-verified knowledge about feature renames and splits
# Assisted-by: LLM

MAPPING_ARCHIVE=reviewed-mappings.zip
MAPPING_ARCHIVE_URL=${MAPPING_ARCHIVE_URL:-https://raw.githubusercontent.com/ekuiter/torte-busybox/refs/heads/clausy-mappings/reviewed-mappings.zip}
MAPPING_MANIFEST=reviewed-mappings-release-pairs.csv
MAPPING_MANIFEST_URL=${MAPPING_MANIFEST_URL:-https://raw.githubusercontent.com/ekuiter/torte-busybox/refs/heads/clausy-mappings/reviewed-mappings/release-pairs.csv}

download-payload-file "$MAPPING_ARCHIVE" "$MAPPING_ARCHIVE_URL"
download-payload-file "$MAPPING_MANIFEST" "$MAPPING_MANIFEST_URL"

BUSYBOX_RELEASE_PAIRS=()
BUSYBOX_RELEASES=()
declare -A BUSYBOX_RELEASE_SET=()
while IFS=, read -r extractor left_release right_release map_file accepted_mappings; do
    [[ -z $extractor || $extractor == extractor ]] && continue
    BUSYBOX_RELEASE_PAIRS+=("$extractor,$left_release,$right_release,$map_file,$accepted_mappings")
    for release in "$left_release" "$right_release"; do
        if [[ -z ${BUSYBOX_RELEASE_SET[$release]} ]]; then
            BUSYBOX_RELEASE_SET[$release]=y
            BUSYBOX_RELEASES+=("$release")
        fi
    done
done < "$(payload-file "$MAPPING_MANIFEST")"

if [[ ${#BUSYBOX_RELEASE_PAIRS[@]} -eq 0 ]]; then
    error-help "No reviewed BusyBox mappings found."
fi

experiment-systems() {
    for revision in "${BUSYBOX_RELEASES[@]}"; do
        add-busybox-kconfig --revision "$revision"
    done
}

experiment-test-systems() {
    experiment-systems
}

# Joins the reviewed release manifest with the extracted model table. Unlike
# compute-file-pairs, this deliberately does not compare every consecutive
# model: it emits only reviewed release boundaries and attaches the mapping
# exported for the corresponding extractor.
#
# Models are indexed by "<extractor group>|<release>" because KClause and
# KConfigReader produce distinct formulas for the same BusyBox release. The
# output schema is consumed by diff-with-clausy:
#   left_model_file,right_model_file,system,variable_map_file
compute-reviewed-file-pairs-helper(file_field, manifest) {
    local pair_csv
    pair_csv="$(input-csv)"
    echo "left_${file_field},right_${file_field},system,variable_map_file" > "$(output-csv)"

    # For example, turn
    #   extract-kconfig-models-with-kclause/busybox/[date]1_3_0.model
    # into the lookup key
    #   extract-kconfig-models-with-kclause/busybox|1_3_0
    declare -A models=()
    while IFS= read -r file; do
        local group name revision
        group=$(dirname "$file")
        name=$(basename "${file%.*}")
        revision=${name#*]}
        models["$group|$revision"]=$file
    done < <(table-field "$pair_csv" "$file_field" | grep -v '^NA$')

    # Each manifest row selects an extractor-specific left/right release pair
    # and the reviewed map that must be used for that comparison. The final
    # accepted_mappings column is informational and is not needed for the join.
    while IFS=, read -r extractor left_release right_release map_file accepted_mappings; do
        [[ -z $extractor || $extractor == extractor ]] && continue
        local group left_file right_file
        group="extract-kconfig-models-with-$extractor/busybox"
        left_file=${models["$group|$left_release"]}
        right_file=${models["$group|$right_release"]}
        if [[ -z $left_file || -z $right_file ]]; then
            error "Missing $extractor model for reviewed BusyBox comparison $left_release -> $right_release."
        fi
        echo "$left_file,$right_file,busybox,reviewed-mappings/$map_file" >> "$(output-csv)"
    done < "$SRC_EXPERIMENT_DIRECTORY/$manifest"
}

compute-reviewed-file-pairs(file_field, input=extract-kconfig-models, output=compute-reviewed-file-pairs, manifest) {
    run \
        --input "$input" \
        --output "$output" \
        --command "$DOCKER_SRC_DIRECTORY/experiment/experiment.sh" \
            compute-reviewed-file-pairs-helper \
            --file-field "$file_field" \
            --manifest "$manifest"
}

experiment-stages() {
    clone-systems
    read-statistics --options skip-sloc

    extract-kconfig-models \
        --with-kconfigreader y \
        --with-kclause y \
        --date-prefix "$(date-format time)"
    join-into read-statistics extract-kconfig-models

    extract-zip \
        --payload-file "$MAPPING_ARCHIVE" \
        --output extract-reviewed-mappings

    compute-reviewed-file-pairs \
        --file-field model_file \
        --manifest "$MAPPING_MANIFEST"

    # run only mapping-aware differences; the original TSE run is the baseline
    diff-with-clausy \
        --file-field model_file \
        --pair-input compute-reviewed-file-pairs \
        --variable-map-input extract-reviewed-mappings \
        --output diff-with-clausy-feature-mappings \
        --timeout 300 \
        --attempts 3 \
        --group-field system \
        --variable-map-field variable_map_file
}

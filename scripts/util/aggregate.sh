#!/bin/bash
# ./aggregate.sh
# merges the output files of two or more stages in a new stage
# assumes that the input directory is the root output directory, also makes some assumptions about its layout

stage_field=$2
file_fields=$3
stage_transformer=${4:-$(lambda-identity)}
stages=("${@:5}")
require-value stage_field stages
compile-lambda stage-transformer "$stage_transformer"
source_transformer="$(lambda value "basename \$(dirname \$(stage-transformer \$value))")"

csv_files=()
for stage in "${stages[@]}"; do
    csv_files+=("$(input-directory)/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv")
    cp -R "$(input-directory)/$stage" "$(output-directory)/$(stage-transformer "$stage")"
done

aggregate-tables "$stage_field" "$source_transformer" "${csv_files[@]}" > "$(output-csv)"
tmp=$(mktemp)
mutate-table-field "$(output-csv)" "$file_fields" "$stage_field" "$(lambda value,context_value echo "\$context_value/\$value")" > "$tmp"
mv "$tmp" "$(output-csv)"
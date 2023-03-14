#!/bin/bash
# ./aggregate.sh
# merges the output files of two or more stages in a new stage
# assumes that each stage's CSV file describes one output file per line
# assumes that the input directory is the root output directory, also makes some assumptions about its layout

# shellcheck source=../../scripts/torte.sh
source torte.sh load-config

file_field=$1
stage_field=$2
common_fields=$3
stage_transformer=$4
stages=("${@:5}")
require-value file_field stage_field common_fields stages
if [[ -z "$stage_transformer" ]]; then
    stage_transformer="cat -"
fi

stage-transformer() {
    stage=$1
    require-value stage
    echo "$stage" | eval "$stage_transformer"
}

echo "$common_fields,$stage_field,$file_field" > "$(output-csv)"
IFS=, read -ra common_fields <<< "$common_fields"
for stage in "${stages[@]}"; do
    old_csv_file="$(input-directory)/$stage.csv"
    while read -r file; do
        old_file="$(input-directory)/$stage/$file"
        new_file="$(output-directory)/$(stage-transformer "$stage")/$file"
        mkdir -p "$(dirname "$new_file")"
        cp "$old_file" "$new_file"
        for common_field in "${common_fields[@]}"; do
            echo -n "$(table-lookup "$old_csv_file" "$file_field" "$file" "$common_field")," >> "$(output-csv)"
        done
        new_file=${new_file#"$(output-directory)/"}
        echo "$(stage-transformer "$stage"),$new_file" >> "$(output-csv)"
    done < <(table-field "$old_csv_file" "$file_field")
done
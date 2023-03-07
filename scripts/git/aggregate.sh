#!/bin/bash
# ./aggregate.sh
# merges the output files of two or more stages in a new stage
# assumes that each stage's CSV file describes one output file per line
# assumes that the input directory is the root output directory

# shellcheck source=../../scripts/main.sh
source main.sh load-config

file_field=$1
stage_field=$2
common_fields=$3
stages=("${@:4}")
require-value file_field stage_field common_fields stages

# todo: hook/eval code for changing the stage (e.g., to only store the iteration in subdirs and csv's)

echo "$common_fields,$stage_field,$file_field" > "$(output-csv)"
IFS=, read -ra common_fields <<< "$common_fields"
for stage in "${stages[@]}"; do
    old_csv_file="$(input-directory)/$stage.csv"
    while read -r file; do
        old_file="$(input-directory)/$stage/$file"
        new_file="$(output-directory)/$stage/$file"
        mkdir -p "$(dirname "$new_file")"
        cp "$old_file" "$new_file"
        for common_field in "${common_fields[@]}"; do
            echo -n "$(table-lookup "$old_csv_file" "$file_field" "$file" "$common_field")," >> "$(output-csv)"
        done
        new_file=${new_file#"$(output-directory)/"}
        echo "$stage,$new_file" >> "$(output-csv)"
    done < <(table-field "$old_csv_file" "$file_field")
done
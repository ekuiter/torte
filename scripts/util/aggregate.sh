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
stage_transformer=${4:-cat -}
stages=("${@:5}")
require-value file_field stage_field stages

stage-transformer() {
    stage=$1
    require-value stage
    echo "$stage" | eval "$stage_transformer"
}

if [[ -n $common_fields ]]; then
    echo -n "$common_fields," > "$(output-csv)"
fi
echo "$stage_field,$file_field" >> "$(output-csv)"
IFS=, read -ra common_fields <<< "$common_fields"
for stage in "${stages[@]}"; do
    old_csv_file="$(input-directory)/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv"
    while read -r file; do
        if [[ $file == NA ]]; then
            new_file=NA
            echo "not all files were available, see NA values:" 1>&2 # todo: better NA reporting
            cat "$old_csv_file" 1>&2
        else
            old_file="$(input-directory)/$stage/$file"
            new_file="$(output-directory)/$(stage-transformer "$stage")/$file"
            mkdir -p "$(dirname "$new_file")"
            cp "$old_file" "$new_file"
            for common_field in "${common_fields[@]}"; do
                echo -n "$(table-lookup "$old_csv_file" "$file_field" "$file" "$common_field")," >> "$(output-csv)"
            done
            new_file=${new_file#"$(output-directory)/"}
            echo "$(stage-transformer "$stage"),$new_file" >> "$(output-csv)"
        fi
    done < <(table-field "$old_csv_file" "$file_field")
done

files=()
for stage in "${stages[@]}"; do
    files+=("$(input-directory)/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv")
done
aggregate-tables "$stage_field" "$stage_transformer" "${files[@]}" > aoeu # todo: rename variables and improve transformer for iterated stages
cat aoeu
mutate-table-field "aoeu" "$file_field" "cat"
error X
#own field for storing na values and errors?
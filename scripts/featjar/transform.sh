#! /bin/bash
# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
jar=/home/FeatJAR/transform/build/libs/transform-0.1.0-SNAPSHOT-all.jar
libs=/home/FeatJAR/transform/libs
file_field=$1
input_extension=$2
output_extension=$3
transformation=$4
timeout=$5
require-value file_field input_extension output_extension transformation timeout

# todo: how to best load z3?
while read -r file; do
    input="$(input-directory)/$file"
    output="$(output-directory)/$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension"
    mkdir -p "$(dirname "$output")"
    LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$libs/" measure-time java \
        -da \
        `# setting a lower memory limit is necessary to avoid that the process is killed erroneously` \
        "-Xmx$(memory-limit 1)G" \
         -cp "$libs/*" \
         -jar $jar \
        --command transform \
        --timeout "${timeout}000" \
        --input "$input" \
        --output "$output" \
        --transformation "$transformation"
done < <(table-field "$(input-csv)" "$file_field")
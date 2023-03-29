#! /bin/bash
# ./transform.sh file-field output-field input-extension output-extension transformation timeout
# transforms files from an input format into an output format using FeatJAR

load-config
jar=/home/FeatJAR/transform/build/libs/transform-0.1.0-SNAPSHOT-all.jar
file_field=$2
input_extension=$3
output_extension=$4
transformation=$5
timeout=$6
require-value file_field input_extension output_extension transformation timeout

echo "$file_field,$output_extension-file,$output_extension-transformation" > "$(output-csv)"
while read -r file; do
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    subject="$transformation: $file"
    log "$subject" "$(echo-yellow transform)"
    measure-time "$timeout" java \
        `# setting a lower memory limit is necessary to avoid that the process is killed erroneously` \
        "-Xmx$(memory-limit 1)G" \
         -jar $jar \
        --command transform \
        --timeout "${timeout}000" \
        --input "$input" \
        --output "$output" \
        --transformation "$transformation"
    if ! is-file-empty "$output"; then
        log "$subject" "$(echo-green "done")"
    else
        log "$subject" "$(echo-red fail)"
        new_file=NA
    fi
    echo "$file,$new_file,$transformation" >> "$(output-csv)"
done < <(table-field "$(input-csv)" "$file_field")
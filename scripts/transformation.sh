#!/bin/bash

z3(timeout) {
    transform-file "$file" smt dimacs SMTToDIMACSZ3 \
        "$(lambda input,output python3 smt2dimacs.py "\$input" "\$output")"
}

kcr() {
    
    transform-file "$file" model dimacs ModelToDIMACSKConfigReader \
        "$(lambda input,output /home/kconfigreader/run.sh de.fosd.typechef.kconfig.TransformIntoDIMACS "\$input" "\$output")"
}

fj() { 
    transform-file "$file" ... ... ... \
        "$(lambda input,output java \
            `# setting a lower memory limit is necessary to avoid that the process is killed erroneously` \
            "-Xmx$(memory-limit 1)G" \
            -jar $jar \
            --command transform \
            --timeout "${timeout}000" \
            --input "\$input" \
            --output "\$output" \
            --transformation "$transformation")"
}

transform-file(file, input_extension, output_extension, transformation, transformer) {
    input="$(input-directory)/$file"
    new_file=$(dirname "$file")/$(basename "$file" ".$input_extension").$output_extension
    output="$(output-directory)/$new_file"
    mkdir -p "$(dirname "$output")"
    subject="$transformation: $file"
    compile-lambda transformer "$transformer"
    log "$subject" "$(echo-progress transform)"
    measure-time "$timeout" "$(transformer "$input" "$output")"
    if ! is-file-empty "$output"; then
        log "$subject" "$(echo-done)"
    else
        log "$subject" "$(echo-fail)"
        new_file=NA
    fi
    echo "$file,$new_file,$transformation"
}

transform-files() {
    echo "$file_field,$output_extension-file,$output_extension-transformation" > "$(output-csv)"
    
    while read -r file; do
        :
        #echo >> "$(output-csv)"
    done < <(table-field "$(input-csv)" "$file_field")
}
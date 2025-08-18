#!/bin/bash
# helpers for working with CSV files

# returns common or exclusive fields of two CSV files
diff-fields(first_file, second_file, flags=-12) {
    comm "$flags" \
        <(head -n1 < "$first_file" | tr , "\n" | sort) \
        <(head -n1 < "$second_file" | tr , "\n" | sort)
}

# returns common fields of any number of CSV files
common-fields(files...) {
    assert-array files
    if [[ ${#files[@]} -eq 1 ]]; then
        head -n1 < "${files[0]}" | tr , "\n" | sort
        return
    fi
    local tmp_1
    tmp_1=$(mktemp)
    local tmp_2
    tmp_2=$(mktemp)
    cat "${files[0]}" > "$tmp_1"
    while [[ ${#files[@]} -ge 2 ]]; do
        files=("${files[@]:1}")
        diff-fields "$tmp_1" "${files[0]}" | tr "\n" , > "$tmp_2"
        cat "$tmp_2" > "$tmp_1"
    done
    tr , "\n" < "$tmp_1"
    rm-safe "$tmp_1" "$tmp_2"
}

# joins two CSV files on the first n fields
# assumes that the first line contains a header and that the string '###' is not used
join-tables-by-prefix(first_file, second_file, n=1) {
    ((n--))
    local escape_sequence=\#\#\#
    join -t, \
        <(replace-times $n , $escape_sequence < "$first_file" | head -n1) \
        <(replace-times $n , $escape_sequence < "$second_file" | head -n1) \
        | replace-times $n $escape_sequence ,
    join -t, \
        <(replace-times $n , $escape_sequence < "$first_file" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        <(replace-times $n , $escape_sequence < "$second_file" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        | replace-times $n $escape_sequence ,
}

# converts field names from stdin into process substitution arguments used by join-two-tables
add-fields(file) {
    xargs -I {} echo -n \<\(table-field "$file" {} y\)" "
}

# joins two CSV files on at least one common field
join-two-tables(first_file, second_file) {
    local common_fields
    common_fields=$(diff-fields "$first_file" "$second_file" -12)
    fields_left=$(diff-fields "$first_file" "$second_file" -23)
    fields_right=$(diff-fields "$first_file" "$second_file" -13)
    local first_file_tmp
    first_file_tmp=$(mktemp)
    local second_file_tmp
    second_file_tmp=$(mktemp)
    eval "paste -d, $(cat <(echo "$common_fields") <(echo "$fields_left") | add-fields "$first_file")" > "$first_file_tmp"
    eval "paste -d, $(cat <(echo "$common_fields") <(echo "$fields_right") | add-fields "$second_file")" > "$second_file_tmp"
    join-tables-by-prefix "$first_file_tmp" "$second_file_tmp" "$(echo "$common_fields" | wc -l)"
    rm-safe "$first_file_tmp" "$second_file_tmp"
}

# joins any number of CSV files on at least one common field
join-tables(files...) {
    assert-array files
    if [[ ${#files[@]} -eq 1 ]]; then
        cat "${files[0]}"
        return
    fi
    local tmp_1
    tmp_1=$(mktemp)
    local tmp_2
    tmp_2=$(mktemp)
    cat "${files[0]}" > "$tmp_1"
    while [[ ${#files[@]} -ge 2 ]]; do
        files=("${files[@]:1}")
        join-two-tables "$tmp_1" "${files[0]}" > "$tmp_2"
        cat "$tmp_2" > "$tmp_1"
    done
    cat "$tmp_1"
    rm-safe "$tmp_1" "$tmp_2"
}

# aggregates any number of CSV files, keeping common fields and adding an aggregate column
aggregate-tables(source_field=, source_transformer=, files...) {
    source_transformer=${source_transformer:-$(lambda-identity)}
    assert-array files
    local common_fields
    compile-lambda source-transformer "$source_transformer"
    readarray -t common_fields < <(common-fields "${files[@]}")
    if [[ -z "${common_fields[*]}" ]]; then
        error "Expected at least one common field."
    fi
    echo -n "$(to-list common_fields)"
    if [[ -n "$source_field" ]]; then
        echo ",$source_field"
    else
        echo
    fi
    local file
    for file in "${files[@]}"; do
        while read -r line; do
            local common_field
            for common_field in "${common_fields[@]}"; do
                if [[ "$common_field" != "${common_fields[0]}" ]]; then
                    echo -n ,
                fi
                echo -n "$(echo "$line" | cut -d, -f"$(table-field-index "$file" "$common_field")")"
            done
            if [[ -n "$source_field" ]]; then
                echo -n ,
                source-transformer "$file"
            else
                echo
            fi
        done < <(tail -n+2 < "$file")
    done
}

# mutates a field in a CSV file
mutate-table-field(file, mutated_fields=, context_field=, field_transformer=) {
    field_transformer=${field_transformer:-$(lambda-identity)}
    to-array mutated_fields
    local fields
    fields=$(head -n1 "$file")
    to-array fields
    compile-lambda field-transformer "$field_transformer"
    to-list fields
    while read -r line; do
        new_line=""
        local current_field
        for current_field in "${fields[@]}"; do
            local value
            value=$(echo "$line" | cut -d, -f"$(table-field-index "$file" "$current_field")")
            if array-contains "$current_field" "${mutated_fields[@]}"; then
                local context_value=""
                if [[ -n $context_field ]]; then
                    context_value=$(echo "$line" | cut -d, -f"$(table-field-index "$file" "$context_field")")
                fi
                new_line+="$(field-transformer "$value" "$context_value"),"
            else
                new_line+="$value,"
            fi
        done
        echo "${new_line::-1}"
    done < <(tail -n+2 < "$file")
}

# gets the index of a named field in a CSV file
table-field-index(file, field) {
    local idx
    idx=$(awk -v col="$field" 'BEGIN {FS=","} NR==1 {for (i=1; i<=NF; i++) if ($i == col) print i; exit}' "$file")
    if [[ -z $idx ]]; then
        error "Table field $field does not exist in file $file."
    fi
    echo "$idx"
}

# gets all values of a named field in a CSV file, optionally including the header
table-field(file, field, include_header=) {
    if [[ $include_header == y ]]; then
        local start_at_line=1
    else
        local start_at_line=2
    fi
    local idx
    idx=$(table-field-index "$file" "$field")
    cut -d, -f"$(table-field-index "$file" "$field")" < "$file" | tail -n+$start_at_line
}

# select field from CSV file where a (primary) key equals a value
table-lookup(file, key, value, field) {
    local idx
    idx=$(table-field-index "$file" "$field")
    if [[ -z "$idx" ]]; then
        error "Field $field not found in file $file."
    fi
    awk -F, '$'"$(table-field-index "$file" "$key")"' == "'"$value"'" {print $'"$idx"'}' < "$file"
}

# returns all fields from a CSV file except the given field
table-fields-except(file, field) {
    head -n1 < "$file" | sed 's/'"$field"'//' | sed 's/,,/,/' | sed 's/,$//g' | sed 's/^,//g'
}
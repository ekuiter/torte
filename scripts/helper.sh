#!/bin/bash

# logs a new message
new-log(arguments...) {
    echo -e "[$DOCKER_PREFIX] \r\033[0K${arguments[*]}"
}

# changes the current log message
update-log(arguments...) {
    echo -e "[$DOCKER_PREFIX] \r\033[1A\033[0K${arguments[*]}"
}

# logs a message that is always printed to the console output
CURRENT_SUBJECT=""
log(subject=, state=) { # todo: make subject optional
    subject=${subject:-$CURRENT_SUBJECT}
    state=${state:-$(echo-progress)}
    local command
    if [[ $subject != "$CURRENT_SUBJECT" ]]; then
        command=new-log
    else
        command=update-log
    fi
    if is-host && ! tail -n1 "$(output-log "$DOCKER_PREFIX")" | grep -q "m$subject\^"; then
        command=new-log
    fi
    CURRENT_SUBJECT=$subject
    "$command" "$(printf %20s "$state")" "$(printf %-80s "$(echo-bold "$subject")")"
}

echo-bold(text=) { echo -e "\033[1m$text\033[0m"; }
echo-red(text=) { echo -e "\033[0;31m$text\033[0m"; }
echo-green(text=) { echo -e "\033[0;32m$text\033[0m"; }
echo-yellow(text=) { echo -e "\033[0;33m$text\033[0m"; }
echo-blue(text=) { echo -e "\033[0;34m$text\033[0m"; }

echo-fail() { echo-red fail; }
echo-progress(state=) { echo-yellow "$state"; }
echo-done() { echo-green "done"; }
echo-skip() { echo-blue skip; }

# logs an error and exit
error(arguments...) {
    echo "${arguments[@]}" 1>&2
    exit 1
}

# appends standard input to a file
write-all(file) {
    tee >(cat -v >> "$file")
}

# appends standard input to a file, omits irrelevant output on console
write-log(file) {
    if [[ $VERBOSE == y ]]; then
        write-all "$file"
    else
        write-all "$file" | grep -oP "\[$DOCKER_PREFIX\] \K.*"
    fi
}

# requires that the given commands are available
require-command(commands...) {
    local command
    for command in "${commands[@]}"; do
        if ! command -v "$command" &> /dev/null; then
            error "Required command $command is missing, please install manually."
        fi
    done
}

# requires that the given variables are non-empty
require-value(variables...) {
    local variable
    for variable in "${variables[@]}"; do
        if [[ -z ${!variable} ]]; then
            error "Required variable $variable is empty, please set it to a non-empty value."
        fi
    done
}

# returns whether we are in a Docker container
is-host() {
    [[ -z $IS_DOCKER_RUNNING ]]
}

# requires that we are not in a Docker container
require-host() {
    if ! is-host; then
        error "Cannot be run inside a Docker container."
    fi
}

# returns whether a function is not defined, useful for providing fallback implementations
unless-function(function) {
    ! declare -F "$function" >/dev/null
}

# returns whether an array is empty
is-array-empty(variable) {
    declare -n variable=$variable
    [[ ${#variable[@]} -eq 0 ]]
}

# requires that an array is not empty
require-array(variable) {
    if is-array-empty "$variable"; then
        error "Required array $variable is empty, please set it to a non-empty value."
    fi
}

# returns whether an array contains a given element
array-contains(element, array...) {
    local e
    for e in "${array[@]}"; do
        [[ "$e" == "$element" ]] && return 0
    done
    return 1
}

# converts a comma-separated list into an array
to-array(variable) {
    IFS=, read -ra "${variable?}" <<< "${!variable}"
}

# prints an array as a comma-separated list
to-list(variable, separator=,,) {
    local list=""
    declare -n variable_reference=$variable
    if is-array-empty "$variable"; then
        return
    fi
    local idx
    for idx in "${!variable_reference[@]}"; do
        list+="${variable_reference[${idx}]}$separator"
    done
    echo "${list::-1}"
}

# creates a lambda function that can be passed around
lambda(arguments, body...) {
    to-array arguments
    echo "() { eval \"\$(parse-arguments lambda ${arguments[*]//,/ })\"; ${body[*]}; }"
}

# a lambda for the identity function
lambda-identity() {
    lambda value echo "\$value"
}

# stores a lambda function as a function in the global namespace
compile-lambda(name, lambda) {
    eval "$name$lambda"
}

# if not defined, defines a function with a given name doing nothing
define-stub(function) {
    eval "unless-function $function && $function() { :; } || true"
}

# replaces a given search string for a given number of times per line, operates on standard input
replace-times(n, search, replace) {
    if [[ $n -eq 0 ]]; then
        cat -
    else
        cat - | sed "s/$search/$replace/" | replace-times $((n-1)) "$search" "$replace"
    fi
}

# returns common or exclusive fields of two CSV files
diff-fields(first_file, second_file, flags=-12) {
    comm "$flags" \
        <(head -n1 < "$first_file" | tr , "\n" | sort) \
        <(head -n1 < "$second_file" | tr , "\n" | sort)
}

# returns common fields of any number of CSV files
common-fields() {
    if [[ $# -eq 0 ]]; then
        error "At least one file expected."
    fi
    if [[ $# -eq 1 ]]; then
        head -n1 < "$1" | tr , "\n" | sort
        return
    fi
    local tmp_1
    tmp_1=$(mktemp)
    local tmp_2
    tmp_2=$(mktemp)
    cat "$1" > "$tmp_1"
    while [[ $# -ge 2 ]]; do
        shift
        diff-fields "$tmp_1" "$1" | tr "\n" , > "$tmp_2"
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

# joins two CSV files on at least one common field
join-two-tables(first_file, second_file) {
    local common_fields
    common_fields=$(diff-fields "$first_file" "$second_file" -12)
    fields_left=$(diff-fields "$first_file" "$second_file" -23)
    fields_right=$(diff-fields "$first_file" "$second_file" -13)
    add-fields(file) {
        xargs -I {} echo -n \<\(table-field "$file" {} y\)" "
    }
    local first_file_tmp
    first_file_tmp=$(mktemp)
    local second_file_tmp
    second_file_tmp=$(mktemp)
    eval "paste -d, $(cat <(echo "$common_fields") <(echo "$fields_left") | add-fields "$first_file")" > "$first_file_tmp"
    eval "paste -d, $(cat <(echo "$common_fields") <(echo "$fields_right") | add-fields "$second_file")" > "$second_file_tmp"
    join-tables-by-prefix "$first_file_tmp" "$second_file_tmp" "$(echo "$common_fields" | wc -l)"
    rm-safe "$first_file_tmp" "$second_file_tmp"
}

# joins any number of CSV files on t least one common fields
join-tables() {
    if [[ $# -eq 0 ]]; then
        error "At least one file expected."
    fi
    if [[ $# -eq 1 ]]; then
        cat "$1"
        return
    fi
    local tmp_1
    tmp_1=$(mktemp)
    local tmp_2
    tmp_2=$(mktemp)
    cat "$1" > "$tmp_1"
    while [[ $# -ge 2 ]]; do
        shift
        join-two-tables "$tmp_1" "$1" > "$tmp_2"
        cat "$tmp_2" > "$tmp_1"
    done
    cat "$tmp_1"
    rm-safe "$tmp_1" "$tmp_2"
}

# aggregates any number of CSV files, keeping common fields and adding an aggregate column
aggregate-tables(source_field, source_transformer=, files...) {
    source_transformer=${source_transformer:-$(lambda-identity)}
    require-array files
    local common_fields
    compile-lambda source-transformer "$source_transformer"
    readarray -t common_fields < <(common-fields "${files[@]}")
    if [[ -z "${common_fields[*]}" ]]; then
        error "Expected at least one common field."
    fi
    echo "$(to-list common_fields),$source_field"
    local file
    for file in "${files[@]}"; do
        # shellcheck disable=SC2094
        while read -r line; do
            local common_field
            for common_field in "${common_fields[@]}"; do
                echo -n "$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$common_field")"),"
            done
            source-transformer "$file"
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
            value=$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$current_field")")
            if array-contains "$current_field" "${mutated_fields[@]}"; then
                local context_value=""
                if [[ -n $context_field ]]; then
                    context_value=$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$context_field")")
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
    idx=$(sed 's/,/\n/g;q' < "$file" | nl | grep "\s$field$" | cut -f1 | xargs)
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
    # shellcheck disable=SC2094
    local idx
    idx=$(table-field-index "$file" "$field")
    cut -d, -f "$(table-field-index "$file" "$field")" < "$file" | tail -n+$start_at_line
}

# select field from CSV file where a (primary) key equals a value
table-lookup(file, key, value, field) {
    local idx
    idx=$(table-field-index "$file" "$field")
    if [[ -z "$idx" ]]; then
        error "Field $field not found in file $file."
    fi
    # shellcheck disable=SC2094
    awk -F, '$'"$(table-field-index "$file" "$key")"' == "'"$value"'" {print $'"$idx"'}' < "$file"
}

# returns all fields from a CSV file except the given field
table-fields-except(file, field) {
    head -n1 < "$file" | sed 's/'"$field"'//' | sed 's/,,/,/' | sed 's/,$//g' | sed 's/^,//g'
}

# silently push directory
push(directory) {
    pushd "$directory" > /dev/null || error "Failed to push directory $directory."
}

# silently pop directory
pop() {
    popd > /dev/null || error "Failed to pop directory."
}

# remove (un-)staged changes and untracked files
git-clean(directory=.) {
    git -C "$directory" reset -q --hard >/dev/null
    git -C "$directory" clean -q -dfx > /dev/null
}

# clean and checkout a revision
git-checkout(revision, directory=.) {
    echo "Checking out $revision in $directory"
    git-clean "$directory"
    git -C "$directory" checkout -q -f "$revision" > /dev/null
}

# list all revisions in version order
git-revisions(system) {
    git -C "$(input-directory)/$system" tag | sort -V
}

# exclude revisions matching a term
exclude-revision(term=, terms...) {
    if [[ -z $term ]]; then
        cat -
    else
        cat - | grep -v "$term" | exclude-revision "${terms[@]}"
    fi
}

# only include revisions starting from a given revision
start-at-revision(start_inclusive=) {
    if [[ -z $start_inclusive ]]; then
        cat -
    else
        sed -n '/'"$start_inclusive"'/,$p'
    fi
}

# only include revisions starting up to a given revision
stop-at-revision(end_exclusive=) {
    if [[ -z $end_exclusive ]]; then
        cat -
    else
        sed -n '/'"$end_exclusive"'/q;p'
    fi
}

# removes files and reports an error when there are permission issues
rm-safe(files...) {
    require-array files
    LC_ALL=C rm -rf "${files[@]}" \
        2> >(grep -q "Permission denied" \
            && error "Could not remove ${files[*]} due to missing permissions, did you run Docker in rootless mode?")
}

# returns the memory limit, optionally adding a further limit
memory-limit(further_limit=0) {
    echo "$((MEMORY_LIMIT-further_limit))"
}

# measures the time needed to execute a command, setting an optional timeout
# if the timeout is 0, no timeout is set
measure-time(timeout, command...) {
    require-array command
    require-command bc # todo: do this without bc, so Dockerfiles can be simpler
    echo "${command[@]}"
    local start
    start=$(date +%s.%N)
    local exit_code
    timeout "$timeout" "${command[@]}" || exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "timeout occurred"
    fi
    local end
    end=$(date +%s.%N)
    echo "time: $(echo "($end - $start) * 1000000000 / 1" | bc)ns"
    echo
}

is-file-empty(file) {
    [[ ! -f "$file" ]] || [[ ! -s "$file" ]]
}

rm-if-empty(file) {
    if is-file-empty "$file"; then
        rm-safe "$file"
    fi
}

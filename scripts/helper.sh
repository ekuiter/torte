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
LOG_START=
log(subject=, state=) {
    subject=${subject:-$CURRENT_SUBJECT}
    state=${state:-$(echo-progress)}
    local command
    if [[ $subject != "$CURRENT_SUBJECT" ]]; then
        CURRENT_SUBJECT=$subject
        command=new-log
        LOG_START=$(date +%s%N)
    else
        command=update-log
    fi
    if is-host && ! tail -n1 "$(output-log "$DOCKER_PREFIX")" | grep -q "m$subject\^"; then
        command=new-log
    fi
    if [[ -n $LOG_START ]] && { [[ $state == $(echo-fail) ]] || [[ $state == $(echo-done) ]]; }; then
        local elapsed_time=$(($(date +%s%N) - LOG_START))
        LOG_START=
    fi
    "$command" "$(printf %30s "$(format-time "$elapsed_time" "" " ")$state")" "$(echo-bold "$subject")"
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

# logs an error and exits
error(arguments...) {
    echo "ERROR: ${arguments[*]}" 1>&2
    exit 1
}

# logs an error, prints help, and exits
error-help(arguments...) {
    echo "ERROR: ${arguments[*]}" 1>&2
    echo 1>&2
    command-help 1>&2
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

# formats a time in nanoseconds in a human-readable way
format-time(nanoseconds=, prefix=, suffix=) {
    if [[ -z $nanoseconds ]]; then
        return
    fi
    local milliseconds="${nanoseconds%??????}"
    echo "$prefix${milliseconds}ms$suffix"
}

# requires that the given commands are available
require-command(commands...) {
    local command
    for command in "${commands[@]}"; do
        if ! command -v "$command" > /dev/null; then
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
    require-command docker make
}

# returns whether a function is defined, useful for providing fallback implementations
has-function(function) {
    declare -F "$function" >/dev/null
}

# returns whether an array (passed as reference) is empty
is-array-empty(variable) {
    variable+='[@]'
    local array=("${!variable}")
    [[ ${#array[@]} -eq 0 ]]
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
    if is-array-empty "$variable"; then
        return
    fi
    variable+='[@]'
    local array=("${!variable}")
    for value in "${array[@]}"; do
        list+="$value$separator"
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
    eval "! has-function $function && $function() { :; } || true"
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
common-fields(files...) {
    require-array files
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
join-tables(files...) {
    require-array files
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
    require-array files
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
                echo -n "$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$common_field")")"
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

# list all tag revisions in version order
git-tag-revisions(system) {
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
evaluate(timeout=0, command...) {
    require-array command
    echo "evaluate_command=${command[*]}"
    local start
    start=$(date +%s%N)
    local exit_code=0
    timeout "$timeout" "${command[@]}" || exit_code=$?
    echo "evaluate_exit_code=$exit_code"
    if [[ $exit_code -eq 124 ]]; then
        echo "evaluate_timeout=y"
    fi
    local end
    end=$(date +%s%N)
    echo "evaluate_time=$((end - start))"
}

# returns whether the given file if is empty
is-file-empty(file) {
    [[ ! -f "$file" ]] || [[ ! -s "$file" ]]
}

# removes the given file if it is empty
rm-if-empty(file) {
    if is-file-empty "$file"; then
        rm-safe "$file"
    fi
}

# sets environment variables dynamically
set-environment(environment=) {
    to-array environment
    for assignment in "${environment[@]}"; do
        eval "export $assignment"
    done
}

# unsets environment variables dynamically
unset-environment(environment=) {
    to-array environment
    for assignment in "${environment[@]}"; do
        unset "$(echo "$assignment" | cut -d= -f1)"
    done
}
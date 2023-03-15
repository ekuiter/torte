#!/bin/bash

# echos and appends to a file
alias append="tee -a"

# logs an error and exit
error() {
    echo "$@" 1>&2
    exit 1
}

# requires that the given commands are available
require-command() {
    for command in "$@"; do
        if ! command -v "$command" &> /dev/null; then
            error "Required command $command is missing, please install manually."
        fi
    done
}

# requires that the given variables are set
require-variable() {
    for var in "$@"; do
        if [[ -z ${!var+x} ]]; then
            error "Required variable $var is not set, please set it to some value."
        fi
    done
}

# requires that the given variables are non-empty
require-value() {
    for var in "$@"; do
        if [[ -z ${!var} ]]; then
            error "Required variable $var is empty, please set it to a non-empty value."
        fi
    done
}

# requires that we are not in a Docker container
require-host() {
    if [[ -n $DOCKER_RUNNING ]]; then
        error "Cannot be run inside a Docker container."
    fi
}

# returns whether a function is not defined, useful for providing fallback implementations
unless-function() { ! declare -F "$1" >/dev/null; }

# if not defined, defines a function with a given name doing nothing
define-stub() {
    function=$1
    require-value function
    eval "unless-function $function && $function() { :; } || true"
}

# replaces a given search string for a given number of times per line, operates on standard input
replace-times() {
    local n=$1
    local search=$2
    local replace=$3
    require-value n search replace
    if [[ $n -eq 0 ]]; then
        cat -
    else
        cat - | sed "s/$search/$replace/" | replace-times $((n-1)) "$search" "$replace"
    fi
}

# returns common or exclusive fields of two CSV files
diff-fields() {
    local first_file=$1
    local second_file=$2
    require-value first_file second_file
    local flags=${3:--12}
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
join-tables-by-prefix() {
    local first_file=$1
    local second_file=$2
    local n=${3:-1}
    ((n--))
    local escape_sequence=\#\#\#
    require-value first_file second_file
    join -t, \
        <(replace-times $n , $escape_sequence < "$first_file" | head -n1) \
        <(replace-times $n , $escape_sequence < "$second_file" | head -n1) \
        | replace-times $n $escape_sequence ,
    join -t, \
        <(replace-times $n , $escape_sequence < "$first_file" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        <(replace-times $n , $escape_sequence < "$second_file" | tail -n+2 | LANG=en_EN sort -k1,1 -t,) \
        | replace-times $n $escape_sequence ,
}

# joins two CSV files on at least one common fields
join-two-tables() {
    local first_file=$1
    local second_file=$2
    require-value first_file second_file
    local common_fields
    common_fields=$(diff-fields "$first_file" "$second_file" -12)
    fields_left=$(diff-fields "$first_file" "$second_file" -23)
    fields_right=$(diff-fields "$first_file" "$second_file" -13)
    add-fields() {
        file=$1
        require-value file
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
aggregate-tables() {
    local source_field=$1
    local source_transformer=${2:-cat -}
    local files=("${@:3}")
    local common_fields
    readarray -t common_fields < <(common-fields "${files[@]}")
    require-value source_field files
    if [[ -z "${common_fields[*]}" ]]; then
        error "Expected at least one common field."
    fi

    source-transformer() {
        value=$1
        require-value value
        echo "$value" | eval "$source_transformer"
    }

    echo "$(IFS=,; echo "${common_fields[*]}"),$source_field"
    for file in "${files[@]}"; do
        # shellcheck disable=SC2094
        while read -r line; do
            for common_field in "${common_fields[@]}"; do
                echo -n "$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$common_field")"),"
            done
            source-transformer "$file"
        done < <(tail -n+2 < "$file")
    done
}

# mutates a field in a CSV file
mutate-table-field() {
    local file=$1
    local field=$2
    local field_transformer=${3:-cat -}
    local fields
    readarray -t fields < <(head -n1 "$file" | tr , "\n")
    require-value file field

    field-transformer() {
        value=$1
        require-value value
        echo "$value" | eval "$field_transformer"
    }

    echo "$(IFS=,; echo "${fields[*]}")"
    # shellcheck disable=SC2094
    while read -r line; do
        new_line=""
        for current_field in "${fields[@]}"; do
            local value
            value=$(echo "$line" | cut -d, -f "$(table-field-index "$file" "$current_field")")
            if [[ $current_field == "$field" ]]; then
                new_line+="$(field-transformer "$value"),"
            else
                new_line+="$value,"
            fi
        done
        echo "${new_line::-1}"
    done < <(tail -n+2 < "$file")
}

# gets the index of a named field in a CSV file
table-field-index() {
    local file=$1
    local field=$2
    require-value file field
    sed 's/,/\n/g;q' < "$file" | nl | grep "$field" | cut -f1 | xargs
}

# gets all values of a named field in a CSV file, optionally including the header
table-field() {
    local file=$1
    local field=$2
    local include_header=$3
    require-value file field
    if [[ $include_header == y ]]; then
        local start_at_line=1
    else
        local start_at_line=2
    fi
    # shellcheck disable=SC2094
    cut -d, -f "$(table-field-index "$file" "$field")" < "$file" | tail -n+$start_at_line
}

# select field from CSV file where a (primary) key equals a value
table-lookup() {
    local file=$1
    local key=$2
    local value=$3
    local field=$4
    require-value file key value field
    local idx
    idx=$(table-field-index "$file" "$field")
    if [[ -z "$idx" ]]; then
        error "Field $field not found in file $file."
    fi
    # shellcheck disable=SC2094
    awk -F, '$'"$(table-field-index "$file" "$key")"' == "'"$value"'" {print $'"$idx"'}' < "$file"
}

# returns all fields from a CSV file except the given field
table-fields-except() {
    local file=$1
    local field=$2
    require-value file field
    head -n1 < "$file" | sed 's/'"$field"'//' | sed 's/,,/,/' | sed 's/,$//g' | sed 's/^,//g'
}

# silently push directory
push() {
    pushd "$@" > /dev/null || error "Failed to push directory $*."
}

# silently pop directory
pop() {
    popd > /dev/null || error "Failed to pop directory."
}

# remove (un-)staged changes and untracked files
git-clean() {
    local directory=${1:-.}
    require-value directory
    git -C "$directory" reset -q --hard >/dev/null
    git -C "$directory" clean -q -dfx > /dev/null
}

# clean and checkout a revision
git-checkout() {
    local revision=$1
    local directory=$2
    require-value revision directory
    echo "Checking out $revision in $directory"
    git-clean "$directory"
    git -C "$directory" checkout -q -f "$revision" > /dev/null
}

# list all revisions in version order
git-revisions() {
    local system=$1
    require-value system
    git -C "$(input-directory)/$system" tag | sort -V
}

# exclude revisions matching a term
exclude-revision() {
    local term=$1
    shift
    if [[ -z $term ]]; then
        cat -
    else
        cat - | grep -v "$term" | exclude-revision "$@"
    fi
}

# only include revisions starting from a given revision
start-at-revision() {
    local start_inclusive=$1
    if [[ -z $start_inclusive ]]; then
        cat -
    else
        sed -n '/'"$start_inclusive"'/,$p'
    fi
}

# only include revisions starting up to a given revision
stop-at-revision() {
    local end_exclusive=$1
    if [[ -z $end_exclusive ]]; then
        cat -
    else
        sed -n '/'"$end_exclusive"'/q;p'
    fi
}

# removes files and reports an error when there are permission issues
rm-safe() {
    LC_ALL=C rm -rf "$@" 2> >(grep -q "Permission denied" && error "Could not remove $* due to missing permissions, did you run Docker in rootless mode?")
}

# returns the memory limit, optionally adding a further limit
memory-limit() {
    require-value MEMORY_LIMIT
    local further_limit=${1:-0}
    echo "$((MEMORY_LIMIT-further_limit))"
}

# measures the time needed to execute a command, setting an optional timeout
# if the timeout is 0, no timeout is set
measure-time() {
    local timeout=$1
    require-value timeout
    require-command bc # todo: do this without bc, so Dockerfiles can be simpler
    local command=("${@:2}")
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

is-file-empty() {
    local file=$1
    require-value file
    [[ ! -f "$file" ]] || [[ ! -s "$file" ]]
}

rm-if-empty() {
    local file=$1
    require-value file
    if is-file-empty "$file"; then
        rm-safe "$file"
    fi
}
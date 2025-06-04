#!/bin/bash
# helpers related to Bash variables and arrays

# asserts that the given variables are non-empty
assert-value(variables...) {
    local variable
    for variable in "${variables[@]}"; do
        if [[ -z ${!variable} ]]; then
            error "Required variable $variable is empty, please set it to a non-empty value."
        fi
    done
}

# returns whether an array (passed as reference) is empty
is-array-empty(variable) {
    variable+='[@]'
    local array=("${!variable}")
    [[ ${#array[@]} -eq 0 ]]
}

# asserts that an array is not empty
assert-array(variable) {
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
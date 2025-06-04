#!/bin/bash
# functions for working with Bash functions

# returns whether a function is defined, useful for providing fallback implementations
has-function(function) {
    declare -F "$function" >/dev/null
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

# allows to pass an existing function as a lambda
to-lambda(name) {
    lambda arguments... "$name" '"${arguments[@]}"'
}

# stores a lambda function as a function in the global namespace
compile-lambda(name, lambda) {
    eval "$name$lambda"
}

# returns all steps of a given hook
get-hook-steps(name) {
    declare -F | cut -d' ' -f3 | grep "^${name}_hook_step_"
}

# returns the most recent identifier of a given hook
get-latest-hook-step-identifier(name) {
    get-hook-steps "$name" | rev | cut -d_ -f1 | rev | sort | tail -n1
}

# stores a new step of a hook function as a function in the global namespace
add-hook-step(name, identifier=, lambda) {
    if [[ -z $identifier ]]; then
        identifier=$(get-latest-hook-step-identifier "$name")
        if [[ -z $identifier ]]; then
            identifier=0
        fi
        identifier=$((identifier+1))
    fi
    compile-lambda "${name}_hook_step_$identifier" "$lambda"
}

# stores a hook function as a function in the global namespace
compile-hook(name) {
    local body=""
    for hook_step in $(get-hook-steps "$name"); do
        body+="\"$hook_step\" \"\${arguments[@]}\";"
    done
    body+=":"
    compile-lambda "$name" "$(lambda arguments... "$body")"
}

# if not defined, defines a function with a given name doing nothing
define-stub(function) {
    eval "! has-function $function && $function() { :; } || true"
}

# memoizes a command by storing its output in the cache
memoize(command...) {
    local hash file
    hash=$(md5sum <<<"${command[*]}" | awk NF=1)
    file=$(output-directory)/$CACHE_DIRECTORY/$hash
    mkdir -p "$(output-directory)/$CACHE_DIRECTORY"
    if [[ ! -f $file ]]; then
        "${command[@]}" | tee "$file"
    else
        cat "$file"
    fi
}
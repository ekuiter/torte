#!/bin/bash
# functions for working with Bash functions

SRC_LAMBDA_DIRECTORY=$SRC_DIRECTORY/lambda # directory to store lambda functions

# returns whether a function is defined, useful for providing fallback implementations
has-function(function) {
    declare -F "$function" >/dev/null
}

# creates a lambda function that can be passed around
# before calling, the lambda must be sourced with source-lambda
lambda(arguments, body...) {
    local hash lambda file
    hash=$(md5sum <<<"$*" | cut -d' ' -f1)
    lambda="__lambda_$hash"
    file="$SRC_LAMBDA_DIRECTORY/$lambda.sh"
    if [[ ! -f $file ]]; then
        mkdir -p "$SRC_LAMBDA_DIRECTORY"
        to-array arguments
        echo "$lambda($(printf '%s, ' "${arguments[@]}" | sed 's/, $//')) { ${body[*]}; }" > "$file"
    fi
    echo "$lambda"
}

# removes all stored lambda functions
# should be called at tool startup
clear-lambdas() {
    rm-safe "$SRC_LAMBDA_DIRECTORY"
}

# a lambda for the identity function
lambda-identity() {
    lambda value echo "\$value"
}

# allows to pass an existing function as a lambda
# can optionally pass arguments for partial application (use this with care, as it does not mixes well with named arguments)
to-lambda(name, curried_arguments...) {
    lambda arguments... "$name" "${curried_arguments[@]}" '"${arguments[@]}"'
}

# stores a lambda function as a function in the global namespace
# must be called before using the lambda the first time
# while this is inelegant (it gives lambdas special treatment), it avoids performance overhead due to frequent resourcing
# lambdas are compiled in memory and not stored on disk to avoid race conditions with parallelized jobs
source-lambda(lambda=) {
    if [[ -n $lambda ]] && ! has-function "$lambda"; then
        # shellcheck disable=SC1090
        source <(compile-script "$SRC_LAMBDA_DIRECTORY/$lambda.sh")
    fi
}

# returns all steps of a given hook
get-hook-steps(name) {
    declare -F | cut -d' ' -f3 | grep "^__hook_${name}_step_"
}

# returns the most recent identifier of a given hook
get-latest-hook-step-identifier(name) {
    get-hook-steps "$name" | rev | cut -d_ -f1 | rev | sort | tail -n1
}

# stores a new step of a hook function as a function in the global namespace
add-hook-step(name, function) {
    eval "__hook_${name}_step_$function() { $function \"\$@\"; }"
}

# stores a hook function as a function in the global namespace
compile-hook(name) {
    local body=""
    for hook_step in $(get-hook-steps "$name"); do
        body+="\"$hook_step\" \"\$@\";"
    done
    eval "${name}() { $body :; }"
}

# if not defined, defines a function with a given name doing nothing
define-stub(function) {
    eval "! has-function $function && $function() { :; } || true"
}

# inside a stage, memoizes a command by storing its output locally
# only memoizes if command returns a result, accounting for non-idempotent functions that start out with "Nothing" and return "Just x" later
# we implement this as a classic bash function instead of memoize(command...)
# this is because this function does not need argument validation anyway, and it improves performance
function memoize-local {
    local hash file
    hash=$(md5sum <<<"$*" | cut -d' ' -f1)
    file=/memoize/$hash
    mkdir -p "/memoize"
    if [[ ! -f $file ]]; then
        "$@" | tee "$file"
        rm-if-empty "$file"
    else
        cat "$file"
    fi
}

# inside a stage, memoizes a command by storing its output in the shared directory (otherwise identical to memoize)
# this is useful to reuse memoized data across different stages
# we have some code duplication here, but it avoids some performance overhead
function memoize-global {
    local hash file
    hash=$(md5sum <<<"$*" | cut -d' ' -f1)
    file=$(output-directory)/$SHARED_DIRECTORY/memoize/$hash
    mkdir -p "$(dirname "$file")"
    if [[ ! -f $file ]]; then
        "$@" | tee "$file"
        rm-if-empty "$file"
    else
        cat "$file"
    fi
}
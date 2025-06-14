#!/bin/bash
# helpers for preparing and running evaluations of commands

# measures the time needed to execute a command, setting an optional timeout
# if the timeout is 0, no timeout is set
evaluate(timeout=0, command...) {
    assert-array command
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
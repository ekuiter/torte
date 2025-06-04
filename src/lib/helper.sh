#!/bin/bash
# miscellaneous helpers
# todo: extract all helpers

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

# returns the earlier revision
min-revision(r1, r2) {
    printf "%s\n" "$r1" "$r2" | sort -V | head -n1
}

# returns the later revision
max-revision(r1, r2) {
    printf "%s\n" "$r1" "$r2" | sort -V | tail -n+2 | head -n1
}

# remove architecture from revision
clean-revision(revision) {
    echo "$revision" | cut -d\[ -f1
}

# get architecture from revision
get-architecture(revision) {
    echo "$revision" | cut -d\[ -f2 | cut -d\] -f1
}

# returns the memory limit, optionally adding a further limit
memory-limit(further_limit=0) {
    echo "$((MEMORY_LIMIT-further_limit))"
}

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

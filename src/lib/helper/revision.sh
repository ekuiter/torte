#!/bin/bash
# helpers for working with revision identifiers

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
# todo: possibly rename architecture to context to make it less Linux-specific?
clean-revision(revision) {
    echo "$revision" | cut -d\[ -f1
}

# get architecture from revision
get-architecture(revision) {
    echo "$revision" | cut -d\[ -f2 | cut -d\] -f1
}
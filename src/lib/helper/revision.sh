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
        awk -v start="$start_inclusive" 'found || $0 == start { found = 1; print }'
    fi
}

# only include revisions up to a given revision
stop-at-revision(end_inclusive=) {
    if [[ -z $end_inclusive ]]; then
        cat -
    else
        awk -v end="$end_inclusive" '{ print } $0 == end { exit }'
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

# enrich a revision with contextual information (e.g., date or architecture)
revision-with-context(revision, context=) {
    if [[ -n $context ]]; then
        echo "$(revision-without-context "$revision")[$context]"
    else
        echo "$revision"
    fi
}

# remove context from revision
revision-without-context(revision) {
    echo "$revision" | cut -d\[ -f1
}

# get context from revision
get-context(revision) {
    echo "$revision" | cut -d\[ -f2 | cut -d\] -f1
}

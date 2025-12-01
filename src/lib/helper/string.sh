#!/bin/bash
# string helpers

# replaces a given search string for a given number of times per line, operates on standard input
replace-times(n, search, replace) {
    if [[ $n -eq 0 ]]; then
        cat -
    else
        cat - | sed "s/$search/$replace/" | replace-times $((n-1)) "$search" "$replace"
    fi
}

# placeholder value for empty parameters (useful for unsetting optional parameters)
none() {
    echo __NONE__
}
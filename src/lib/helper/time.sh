#!/bin/bash
# date and time helper functions

# formats a time in nanoseconds in a human-readable way
format-time(nanoseconds=, prefix=, suffix=) {
    if [[ -z $nanoseconds ]]; then
        return
    fi
    local milliseconds="${nanoseconds%??????}"
    if [[ $milliseconds -lt 1000 ]]; then
        echo "$prefix${milliseconds}ms$suffix"
    elif [[ $milliseconds -lt 60000 ]]; then
        local seconds="${nanoseconds%?????????}"
        echo "$prefix${seconds}s$suffix"
    else
        local minutes
        minutes="$((${nanoseconds%?????????}/60))"
        echo "$prefix${minutes}m$suffix"
    fi
}

# returns intervals in seconds
interval(name) {
    if [[ "$name" == hourly ]]; then
        echo $((60*60))
    elif [[ "$name" == daily ]]; then
        echo $(($(interval hourly)*24))
    elif [[ "$name" == weekly ]]; then
        echo $(($(interval daily)*7))
    elif [[ "$name" == monthly ]]; then
        echo $(($(interval yearly)/12))
    elif [[ "$name" == yearly ]]; then
        echo $(($(interval daily)*365+$(interval daily)/4))
    elif [[ "$name" == per-decade ]]; then
        echo $(($(interval yearly)*10))
    fi
}
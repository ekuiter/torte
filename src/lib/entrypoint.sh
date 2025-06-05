#!/bin/bash
# initializes and runs the tool

entrypoint(arguments...) {
    # load experiment file
    if [[ ${#arguments[@]} -ge 1 ]] && [[ -n "$(experiment-file "${arguments[0]}")" ]]; then
        load-experiment "${arguments[0]}"
        arguments=("${arguments[@]:1}")
    elif [[ ${#arguments[@]} -ge 1 ]] && ! has-function "${arguments[0]}"; then
        error-help "${arguments[0]} is neither an experiment file nor a function."
    else
        load-experiment
    fi

    # initialization done (todo: avoid this?)
    INITIALIZED=y

    # identify which command to run (default: command-run)
    if [[ -z "${arguments[*]}" ]]; then
        arguments=(run)
    fi
    function=${arguments[0]}

    # on the host, internal commands can be shadowed with user-facing commands (prefixed with command-)
    if is-host && has-function "command-$function"; then
        function=command-$function
    fi
    
    # run the given command
    "$function" "${arguments[@]:1}"
}
#!/bin/bash

entrypoint(arguments...) {
    # define stubs for API functions
    for function in "${API[@]}"; do
        define-stub "$function"
    done

    # load experiment file
    if [[ ${#arguments[@]} -ge 1 ]] && [[ -f "${arguments[0]}" ]]; then 
        load-experiment "${arguments[0]}"
        arguments=("${arguments[@]:1}")
    else
        load-experiment
    fi

    # initialization done
    INITIALIZED=y

    # run the given command
    if [[ -z "${arguments[*]}" ]]; then
        arguments=(run)
    fi
    function=${arguments[0]}
    if is-host && has-function "command-$function"; then
        function=command-$function
    fi
    "$function" "${arguments[@]:1}"
}
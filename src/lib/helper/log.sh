#!/bin/bash
# logging facilities

# logs a new message
new-log(arguments...) {
    echo -e "[$TOOL] \r\033[0K${arguments[*]}"
}

# changes the current log message
update-log(arguments...) {
    echo -e "[$TOOL] \r\033[1A\033[0K${arguments[*]}"
}

# logs a message that is always printed to the console output
log(subject=, state=) {
    subject=${subject:-$CURRENT_SUBJECT}
    state=${state:-$(echo-progress)}
    local command
    if [[ $subject != "$CURRENT_SUBJECT" ]]; then
        CURRENT_SUBJECT=$subject
        command=new-log
        LOG_START=$(date +%s%N)
    else
        command=update-log
    fi
    # todo: this is pretty complicated logic for a corner case and can probably be done in a smarter way
    if [[ -n $INITIALIZED ]] && is-host && has-function stage-log && [[ -f $(stage-log "$TOOL") ]] && ! tail -n1 "$(stage-log "$TOOL")" | grep -q "m$subject\^"; then
        command=new-log
    fi
    if [[ -n $LOG_START ]] && { [[ $state == $(echo-fail) ]] || [[ $state == $(echo-done) ]]; }; then
        local elapsed_time
        elapsed_time=$(($(date +%s%N) - LOG_START))
        LOG_START=
    fi
    "$command" "$(printf %30s "$(format-time "$elapsed_time" "" " ")$state")" "$(echo-bold "$subject")"
}

echo-bold(text=) { echo -e "\033[1m$text\033[0m"; }
echo-red(text=) { echo -e "\033[0;31m$text\033[0m"; }
echo-green(text=) { echo -e "\033[0;32m$text\033[0m"; }
echo-yellow(text=) { echo -e "\033[0;33m$text\033[0m"; }
echo-blue(text=) { echo -e "\033[0;34m$text\033[0m"; }

echo-fail() { echo-red fail; }
echo-progress(state=) { echo-yellow "$state"; }
echo-done() { echo-green "done"; }
echo-note(state=) { echo-blue "$state"; }
echo-skip() { echo-note skip; }

# logs an error and exits
error(arguments...) {
    echo "ERROR: ${arguments[*]}" 1>&2
    exit 1
}

# logs an error, prints help, and exits
error-help(arguments...) {
    echo "ERROR: ${arguments[*]}" 1>&2
    command-help 1>&2
    exit 1
}

# appends standard input to a file
write-all(file) {
    tee >(cat -v >> "$file")
}

# appends standard input to a file, omits irrelevant output on console
write-log(file) {
    if [[ $VERBOSE == y ]]; then
        write-all "$file"
    else
        write-all "$file" | grep -oP "\[$TOOL\] \K.*"
    fi
}
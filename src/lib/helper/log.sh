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

# detailed and readable logging in CI environments
# we override this here once to avoid repeated checks for CI
if [[ -n "$CI" ]]; then
    VERBOSE=y
    
    new-log(arguments...) {
        echo -e "${arguments[*]}"
    }

    update-log(arguments...) {
        echo -e "${arguments[*]}"
    }
fi

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
    if [[ -n $FORCE_NEW_LOG ]]; then
        command=new-log
        FORCE_NEW_LOG=
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
error(__NO_PROFILE__, arguments...) {
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

# runs a command while showing a rolling preview of its latest output lines.
# the command's full output is captured in a temporary file, while the terminal
# only shows the latest few lines and redraws them in place. We write the
# preview to /dev/tty when possible, because compact experiment execution pipes
# stdout through write-log, which intentionally filters non-torte log lines.
# If the command fails, the full captured output is printed afterwards.
run-with-rolling-tail(lines=5, command...) {
    local log_file
    log_file=$(mktemp)
    local shown_lines=0
    local rolling_tail_output=/dev/stderr
    if [[ -t 2 ]] && [[ -w /dev/tty ]]; then
        rolling_tail_output=/dev/tty
    fi
    cleanup-rolling-tail() {
        clear-rolling-tail "$shown_lines"
        rm-safe "$log_file"
        rm-safe "$log_file.status"
    }
    trap cleanup-rolling-tail RETURN INT TERM

    {
        "${command[@]}" > "$log_file" 2>&1
        echo "$?" > "$log_file.status"
    } &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        draw-rolling-tail-from-file "$log_file" "$lines" "$shown_lines"
        shown_lines=$DRAWN_ROLLING_TAIL_LINES
        sleep 1
    done

    local wait_status status
    wait "$pid"
    wait_status=$?
    draw-rolling-tail-from-file "$log_file" "$lines" "$shown_lines"
    shown_lines=$DRAWN_ROLLING_TAIL_LINES
    status=$(cat "$log_file.status" 2>/dev/null)
    status=${status:-$wait_status}
    clear-rolling-tail "$shown_lines"
    shown_lines=0

    if [[ $status -ne 0 ]]; then
        cat "$log_file" >&2
    fi
    cleanup-rolling-tail
    trap - RETURN INT TERM
    return "$status"
}

# redraws a rolling preview from a captured output file
draw-rolling-tail-from-file(file, lines=5, shown_lines=0) {
    local current_lines=()
    if [[ -s $file ]]; then
        readarray -t current_lines < <(tail -n "$lines" "$file" | tr '\r' '\n' | tail -n "$lines")
    fi
    draw-rolling-tail "$shown_lines" "${current_lines[@]}"
}

# redraws the given lines, first clearing the lines drawn by the previous preview
draw-rolling-tail(shown_lines=0, current_lines...) {
    clear-rolling-tail "$shown_lines"
    local columns=${COLUMNS:-}
    if [[ ! $columns =~ ^[0-9]+$ ]]; then
        columns=$(tput cols 2>/dev/null || echo 120)
    fi
    local line
    for line in "${current_lines[@]}"; do
        printf "%.*s\n" "$columns" "$line" > "$rolling_tail_output"
    done
    DRAWN_ROLLING_TAIL_LINES=${#current_lines[@]}
}

# clears a previously drawn rolling preview
clear-rolling-tail(shown_lines=0) {
    local i
    for ((i = 0; i < shown_lines; i++)); do
        printf "\033[1A\033[2K" > "$rolling_tail_output"
    done
}

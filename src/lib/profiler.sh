#!/bin/bash
# a small profiler for Bash functions, tracking call counts and execution times, which can be used to make flame graphs

# record the stack trace and duration of a function call, called by preprocessor.sh
# __NO_PROFILE__ is a special flag to indicate that profiling is disabled to avoid the profiler recursively calling itself
# some functions are inlined here for the same reason
record-function-call(__NO_PROFILE__, function_name, stack_trace, duration_us) {
    if [[ -z $PROFILE ]]; then
        return
    fi
    local profile_file
    # inline is-host
    if [[ -z $INSIDE_STAGE ]]; then
        # inline stages-directory + stage-directory
        local stage_dir
        if [[ -z $PASS ]]; then
            stage_dir="$STAGES_DIRECTORY/0_$EXPERIMENT_STAGE"
        else
            stage_dir="$STAGES_DIRECTORY/$PASS/0_$EXPERIMENT_STAGE"
        fi
        mkdir -p "$stage_dir"
        # inline stage-prf
        profile_file="$stage_dir/$OUTPUT_FILE_PREFIX.prf"
    else
        # inline output-prf
        profile_file="$DOCKER_OUTPUT_DIRECTORY/$OUTPUT_FILE_PREFIX.prf"
    fi
    if [[ ! -f $profile_file ]]; then
        echo "stage,function,stack,calls,total_time_us" > "$profile_file"
    fi
    local stage=${INSIDE_STAGE:-$EXPERIMENT_STAGE}
    echo "$stage,$function_name,$stack_trace,1,$duration_us" >> "$profile_file"
}

# combine multiple profile files
combine-profiles(input_files...) {
    echo "stage,function,stack,calls,total_time_us"
    for file in "${input_files[@]}"; do
        if [[ -f $file ]]; then
            tail -n +2 "$file"
        fi
    done
}

# combine profiling data from all stages recursively
combine-stage-profiles() {
    local profile_files=()
    readarray -t profile_files < <(find "$(stages-directory)" -name "$OUTPUT_FILE_PREFIX.prf" -type f 2>/dev/null | sort -t'/' -k2 -n)
    if [[ ${#profile_files[@]} -gt 0 ]]; then
        combine-profiles "${profile_files[@]}"
    else
        echo "No profile files found to combine"
    fi
}

# create a speedscope-compatible collapsed stack format
# see https://github.com/jlfwong/speedscope/wiki/Importing-from-custom-sources#brendan-greggs-collapsed-stack-format
convert-to-speedscope() {
    tail -n +2 | \
        awk -F, '{ 
            dur_ms = int($5 / 1000); 
            stage = $1;
            stack = $3; 
            calls = $4; 
            # reverse the stack order for speedscope (root-to-leaf)
            n = split(stack, frames, ";");
            reversed = "";
            for(j = n; j >= 1; j--)
            {
                if (reversed == "") reversed = frames[j];
                else reversed = reversed ";" frames[j];
            }
            # prepend stage name to the stack trace
            reversed = stage ";" reversed;
            for(i = 0; i < calls; i++)
            { 
                print reversed " " dur_ms;
            } 
        }'
}

# save a speedscope-compatible collapsed stack format for inspection in the browser
save-speedscope(file=) {
    file=${file:-$(stage-path "$EXPERIMENT_STAGE" "$OUTPUT_FILE_PREFIX.speedscope")}
    combine-stage-profiles | convert-to-speedscope > "$file"
}

# open the profiling data with speedscope in the browser
# alternatively use https://www.speedscope.app/ manually
open-speedscope(file=) {
    file=${file:-$(stage-path "$EXPERIMENT_STAGE" "$OUTPUT_FILE_PREFIX.speedscope")}
    assert-command npm
    npm install -g speedscope
    save-speedscope "$file"
    speedscope "$file"
}

# find all functions defined by the tool
# as a side effect, loads all stage helpers, so this should be used sparingly
list-functions() {
    define-stages
    declare -F | grep "declare -f " | cut -d' ' -f3 | grep -E '^[a-z][a-z0-9-]*$' | sed 's/^command-//' | sort | uniq
}

# detect dead code by comparing defined functions with all profiled functions
# ideally the only uncalled functions are those that are never profiled (i.e., they are only called during initialization)
detect-dead-code() {
    local profile_data
    profile_data=$(combine-stage-profiles)
    echo "Functions called but not defined:"
    comm -13 <(list-functions) <(echo "$profile_data" | tail -n +2 | cut -d, -f2 | sort -u)
    echo ""
    echo "Functions defined but never called:"
    comm -23 <(list-functions) <(echo "$profile_data" | tail -n +2 | cut -d, -f2 | sort -u)
}
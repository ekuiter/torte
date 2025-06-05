#!/bin/bash
# a small magical preprocessor for Bash scripts that allows more succinct function definitions
# e.g., the syntax fn(a, b, c=3) { echo $a $b $c; } does not usually work in Bash, but this preprocessor makes it work
# depends some primitives defined in lib/helper (assert-host and log)
# preprocessed scripts should lie in the same directory tree as this script

# the location of this script
BOOTSTRAP_DIRECTORY=$(dirname "$0")

# a shortcut to recursively call this script
BOOTSTRAP_SCRIPT=(/usr/bin/env bash "$BOOTSTRAP_DIRECTORY"/bootstrap.sh)

# where to store the preprocessed scripts (should be below the bootstrap directory)
GEN_DIRECTORY=$BOOTSTRAP_DIRECTORY/gen

# requires the GNU version of sed
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed() {
        if ! command -v gsed > /dev/null; then
            echo "Required command gsed is missing, please install manually." 1>&2
            rm -rf "$GEN_DIRECTORY"
            exit 1
        fi
        gsed "$@"
    }
fi

# compiles the given script
compile-script() {
    local script=$1
    # match all Bash function definitions, which consists of the following:
    # whitespace, a function name, whitespace, (, parameter specification, ), whitespace, {, anything
    local regex='^\s*([a-z0-9-]+)\s*\((.*)\)\s*\{(.*)'

    # interpreted version (very slow due to eval and it requires parse-arguments to be in scope)
    # sed -E 's/'"$regex"'/\1() { eval "$(parse-arguments \1 \2)"; \3/' < "$script"

    # compiled version (much faster, but also harder to understand)
    # #e is a GNU sed extension that allows executing the replacement as a command
    # we recursively call this script, which in turn calls parse-arguments, the results of which will be inserted by sed
    sed -E "s#$regex#echo '\1() {' \$(${BOOTSTRAP_SCRIPT[*]} \"\1\" \2) '\3'#e" < "$script"
}

# improves Bash's sourcing mechanism so scripts are compiled before inclusion
source-script() {
    local script=$1
    # this code is specific to this project to improve logging
    if declare -F log >/dev/null; then
        if [[ -z $CURRENT_SUBJECT ]]; then
            log "loading scripts"
        fi
        log "${script#"$SRC_DIRECTORY"/}" "$(echo-progress load)"
    fi
    local generated_script_directory generated_script
    generated_script_directory=$(dirname "$script")
    generated_script_directory=${generated_script_directory#"$BOOTSTRAP_DIRECTORY"/} # remove the bootstrap directory from a composite path
    generated_script_directory=${generated_script_directory#"$BOOTSTRAP_DIRECTORY"} # remove the bootstrap directory from a root-level path
    generated_script_directory=$GEN_DIRECTORY/$generated_script_directory
    local -r generated_script=$generated_script_directory/$(basename "$script")
    mkdir -p "$generated_script_directory"
    # inside of Docker containers, make may not be installed (but also not required, as the generated script it has already been copied into the container)
    if command -v make > /dev/null; then
        # we want to use make to avoid recompiling the script if it has not changed
        # to do this, we pass make a temporary makefile created with <(...)
        # the makefile contains a rule that preprocesses each script into a corresponding script in the gen directory
        # the rule itself recursively calls this script with the original file ($<) and writes its output (>) to the generated script ($@)
        make -f <(printf "%s\n\t%s\n" "$GEN_DIRECTORY"'/%.sh : '"$BOOTSTRAP_DIRECTORY"'/%.sh' "${BOOTSTRAP_SCRIPT[*]}"' $< > $@') "$generated_script" > /dev/null
    fi
    # shellcheck source=/dev/null
    source "$generated_script"
    # this code is specific to this project to improve logging
    if [[ -n $CURRENT_SUBJECT ]]; then
        log "" "$(echo-done)"
    fi
}

# generates code that parses function arguments in a flexible way, which is pretended to the function body
# e.g., fn(a, b, c=3) can be called with positional arguments as "fn 1 2 3" or with named arguments as "fn --a 1 --b 2"
# allows default values and variadic arguments
parse-arguments() {
    local function_name=$1
    local param_specs=("${@:2}")
    local code=""
    local i=0
    local variadic=""
    local param_spec
    local variable

    # shellcheck disable=SC2001
    preprocess() { echo "$1" | sed s/,$//; }

    # assume default values
    for param_spec in "${param_specs[@]}"; do
        param_spec=$(preprocess "$param_spec")
        if [[ $variadic == y ]]; then
            code+="error \"Function $function_name can only have one variadic argument, which must be the last.\"; "
            break
        fi
        if [[ $param_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$param_spec" | cut -d. -f1)
            code+="local $variable; $variable=(); "
            variadic=y
        elif [[ $param_spec =~ = ]]; then
            local default_value
            default_value=$(echo "$param_spec" | cut -d= -f2)
            variable=$(echo "$param_spec" | cut -d= -f1)
            code+="local $variable; $variable=$default_value; "
        else
            variable=$param_spec
            code+="local $variable; $variable=\"\"; "
        fi
    done
    
    # parse positional arguments
    code+="if [[ ! \$1 == \"--\"* ]]; then "
    for param_spec in "${param_specs[@]}"; do
        param_spec=$(preprocess "$param_spec")
        ((i+=1))
        if [[ $param_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$param_spec" | cut -d. -f1)
            code+="$variable=(\"\${@:$i}\"); "
            continue
        elif [[ $param_spec =~ = ]]; then
            variable=$(echo "$param_spec" | cut -d= -f1)
        else
            variable=$param_spec
        fi
        code+="$variable=\${$i:-\$$variable}; "
    done
    if [[ -z $variadic ]]; then
        code+="if [[ \$# -gt ${#param_specs[@]} ]]; then "
        code+="error \"Function $function_name expects ${#param_specs[@]} arguments, but got \$# arguments.\"; "
        code+="fi; "
    fi

    # parse named arguments
    code+="else "
    code+="while [[ \$# -gt 0 ]]; do "
    code+="local argument=\${1/--/}; argument=\${argument//-/_}; "
    code+="if false; then :; "
    for param_spec in "${param_specs[@]}"; do
        param_spec=$(preprocess "$param_spec")
        if [[ $param_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$param_spec" | cut -d. -f1)
            code+="elif [[ \"$variable\" == \"\$argument\" ]]; then "
            code+="shift; while [[ \$# -gt 0 ]]; do $variable+=(\"\$1\"); shift; done; "
            continue
        elif [[ $param_spec =~ = ]]; then
            variable=$(echo "$param_spec" | cut -d= -f1)
        else
            variable=$param_spec
        fi
        code+="elif [[ \"$variable\" == \"\$argument\" ]]; then "
        code+="shift; $variable=\${1:-\$$variable}; shift; "
    done
    code+="else "
    code+="error \"Function $function_name got parameter \$argument, which was not expected.\"; "
    code+="fi; "
    code+="done; "
    code+="fi; "

    # assert required parameters
    for param_spec in "${param_specs[@]}"; do
        param_spec=$(preprocess "$param_spec")
        if [[ $param_spec =~ \.\.\.$ ]]; then
            continue
        elif [[ $param_spec =~ = ]]; then
            continue
        else
            variable=$param_spec
            code+="if [[ -z \$$variable ]]; then "
            code+="error \"Function $function_name requires parameter $variable, which has not been set.\"; "
            code+="fi; "
        fi
    done

    # decorate special functions that should only be run on the host (requires helper.sh to be in scope)
    # this code is specific to this project and can be removed if only simple argument preprocessing is needed
    if [[ $function_name =~ ^command- ]]; then
        code+="assert-host; "
    fi

    echo "$code"
}

# run only if this script was executed stand-alone
if [[ -z $TOOL ]]; then
    if [[ $# -eq 1 ]] && [[ -f $1 ]]; then
        # compile the given script
        compile-script "$1"
    else
        # generate code for argument parsing
        parse-arguments "$@"
    fi
fi

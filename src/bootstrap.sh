#!/bin/bash
# a small preprocessor for Bash scripts that allows more succinct function definitions
# e.g., fn(a, b, c=3) { echo $a $b $c; } it does not usually work in bash, but this preprocessor makes it work
# depends on some helpers defined in helper.sh

# requires the GNU version of sed
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed() {
        if ! command -v gsed > /dev/null; then
            echo "Required command gsed is missing, please install manually." 1>&2
            find "$(dirname "$0")" -name '*.gen.sh' -delete 1>&2
            exit 1
        fi
        gsed "$@"
    }
fi

# compiles the given script
compile-script() {
    local script=$1
    local regex='^\s*([a-z0-9-]+)\s*\((.*)\)\s*\{(.*)'
    # sed -E 's/'"$regex"'/\1() { eval "$(parse-arguments \1 \2)"; \3/' < "$script" # interpreted version
    sed -E "s#$regex#echo '\1() {' \$(/bin/bash $(dirname "$0")/bootstrap.sh \"\1\" \2) '\3'#e" < "$script" # compiled version
}

# improves Bash's sourcing mechanism so scripts are compiled before inclusion
source-script() {
    local script
    script=$1
    local generated_script
    local -r generated_script=$(dirname "$script")/$(basename "$script" .sh).gen.sh
    # in Docker containers, make may not be installed (but also not required, as the generated script is already copied into the container)
    if command -v make > /dev/null; then
        make -f <(printf "%s\n\t%s\n" '%.gen.sh : %.sh' '/bin/bash '"$(dirname "$0")"'/bootstrap.sh $< > $@') "$generated_script" > /dev/null
    fi
    # shellcheck source=/dev/null
    source "$generated_script"
}

# generates code that parses function arguments in a flexible way
# e.g., fn(a, b, c=3) can be called with positional arguments as "fn 1 2 3" or with named arguments as "fn --a 1 --b 2"
# allows default values and variadic arguments
parse-arguments() {
    local function_name=$1
    local variable_specs=("${@:2}")
    local code=""
    local i=0
    local variadic=""
    local variable_spec
    local variable

    # shellcheck disable=SC2001
    preprocess() { echo "$1" | sed s/,$//; }

    # assume default values
    for variable_spec in "${variable_specs[@]}"; do
        variable_spec=$(preprocess "$variable_spec")
        if [[ $variadic == y ]]; then
            code+="error \"Function $function_name can only have one variadic argument, which must be the last.\"; "
            break
        fi
        if [[ $variable_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$variable_spec" | cut -d. -f1)
            code+="local $variable; $variable=(); "
            variadic=y
        elif [[ $variable_spec =~ = ]]; then
            local default_value
            default_value=$(echo "$variable_spec" | cut -d= -f2)
            variable=$(echo "$variable_spec" | cut -d= -f1)
            code+="local $variable; $variable=$default_value; "
        else
            variable=$variable_spec
            code+="local $variable; $variable=\"\"; "
        fi
    done
    
    # parse positional arguments
    code+="if [[ ! \$1 == \"--\"* ]]; then "
    for variable_spec in "${variable_specs[@]}"; do
        variable_spec=$(preprocess "$variable_spec")
        ((i+=1))
        if [[ $variable_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$variable_spec" | cut -d. -f1)
            code+="$variable=(\"\${@:$i}\"); "
            continue
        elif [[ $variable_spec =~ = ]]; then
            variable=$(echo "$variable_spec" | cut -d= -f1)
        else
            variable=$variable_spec
        fi
        code+="$variable=\${$i:-\$$variable}; "
    done
    if [[ -z $variadic ]]; then
        code+="if [[ \$# -gt ${#variable_specs[@]} ]]; then "
        code+="error \"Function $function_name expects ${#variable_specs[@]} arguments, but got \$# arguments.\"; "
        code+="fi; "
    fi

    # parse named arguments
    code+="else "
    code+="while [[ \$# -gt 0 ]]; do "
    code+="local argument=\${1/--/}; argument=\${argument//-/_}; "
    code+="if false; then :; "
    for variable_spec in "${variable_specs[@]}"; do
        variable_spec=$(preprocess "$variable_spec")
        if [[ $variable_spec =~ \.\.\.$ ]]; then
            variable=$(echo "$variable_spec" | cut -d. -f1)
            code+="elif [[ \"$variable\" == \"\$argument\" ]]; then "
            code+="shift; while [[ \$# -gt 0 ]]; do $variable+=(\"\$1\"); shift; done; "
            continue
        elif [[ $variable_spec =~ = ]]; then
            variable=$(echo "$variable_spec" | cut -d= -f1)
        else
            variable=$variable_spec
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
    for variable_spec in "${variable_specs[@]}"; do
        variable_spec=$(preprocess "$variable_spec")
        if [[ $variable_spec =~ \.\.\.$ ]]; then
            continue
        elif [[ $variable_spec =~ = ]]; then
            continue
        else
            variable=$variable_spec
            code+="if [[ -z \$$variable ]]; then "
            code+="error \"Function $function_name requires parameter $variable, which has not been set.\"; "
            code+="fi; "
        fi
    done

    # decorate special functions that should only be run on the host
    # this code is specific to this project and can be removed if only simple argument preprocessing is needed
    if [[ $function_name =~ ^command- ]]; then
        code+="require-host; "
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

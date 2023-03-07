#!/bin/bash

# runs a stage of some experiment in a Docker container
# reads the global CONFIG_FILE variable
run-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    require-host
    require-value CONFIG_FILE stage dockerfile input_directory
    exec > >(append "$(output-log main)")
    exec 2> >(append "$(output-err main)" >&2)
    local flags=
    if [[ $# -lt 4 ]]; then
        command=(/bin/bash)
        flags=-it
    else
        command=("${@:4}")
    fi
    if [[ ! -f $(output-log "$stage") ]]; then
        echo "Running stage $stage"
        rm -rf "$(output-prefix "$stage")*"
        if [[ $SKIP_DOCKER_BUILD != y ]]; then
            cp "$CONFIG_FILE" "$SCRIPTS_DIRECTORY/_config.sh"
            docker build \
                -f "$dockerfile"\
                -t "${DOCKER_PREFIX}_$stage" \
                --ulimit nofile=20000:20000 \
                "$SCRIPTS_DIRECTORY"
        fi
        mkdir -p "$(output-directory "$stage")"
        docker run $flags \
            -v "$PWD/$input_directory:$DOCKER_INPUT_DIRECTORY" \
            -v "$PWD/$(output-directory "$stage"):$DOCKER_OUTPUT_DIRECTORY" \
            -e DOCKER_RUNNING=y \
            --rm \
            "${DOCKER_PREFIX}_$stage" \
            "${command[@]}" \
            > >(append "$(output-log "$stage")") \
            2> >(append "$(output-err "$stage")" >&2)
        copy-output-files "$stage"
        rmdir --ignore-fail-on-non-empty "$(output-directory "$stage")"
    else
        echo "Skipping stage $stage"
    fi
}

# runs a stage a given number of time and merges the output files in one aggregate stage
# assumes that the iterated stage's CSV file describes one output file per line
run-iterated-stage() {
    local aggregate_stage=$1
    local iterations=$2
    local file_field=$3
    local stage_field=$4
    local dockerfile=$5
    local input_directory=$6
    require-host
    require-value aggregate_stage iterations dockerfile input_directory
    local stages=()
    for i in $(seq "$iterations"); do
        local stage="${aggregate_stage}_$i"
        stages+=("$stage")
        run-stage "$stage" "$dockerfile" "$input_directory" "${@:7}"
    done
    local common_fields
    common_fields=$(table-fields-except "$(output-csv "${aggregate_stage}_1")" "$file_field")
    run-aggregate-stage "$aggregate_stage" "$file_field" "$stage_field" "$common_fields" "${stages[@]}"
}

# merges the output files of two or more stages in one aggregate stage
# assumes that each stage's CSV file describes one output file per line
run-aggregate-stage() {
    local aggregate_stage=$1
    local file_field=$2
    local stage_field=$3
    local common_fields=$4
    local stages=("${@:5}")
    require-host
    require-value aggregate_stage file_field stage_field common_fields stages
    if [[ ! -f $(output-log "$aggregate_stage") ]]; then
        echo "Running stage $aggregate_stage"
        local aggregate_directory="$OUTPUT_DIRECTORY/$aggregate_stage"
        echo "$common_fields,$stage_field,$file_field" > "$(output-csv "$aggregate_stage")"
        IFS=, read -ra common_fields <<< "$common_fields"
        for stage in "${stages[@]}"; do
            while read -r file; do
                local new_file="$aggregate_directory/$stage/$file"
                mkdir -p "$(dirname "$new_file")"
                cp "$OUTPUT_DIRECTORY/$stage/$file" "$new_file"
                for common_field in "${common_fields[@]}"; do
                    echo -n "$(table-lookup "$(output-csv "$stage")" "$file_field" "$file" "$common_field")," >> "$(output-csv "$aggregate_stage")"
                done
                new_file=${new_file#"$aggregate_directory/"}
                # todo: hook/eval code for changing the stage (e.g., to only store the iteration)
                echo "$stage,$new_file" >> "$(output-csv "$aggregate_stage")"
            done < <(table-field "$(output-csv "$stage")" "$file_field")
        done
        touch "$(output-log "$aggregate_stage")"
    else
        echo "Skipping stage $aggregate_stage"
    fi
}

# prepares an experiment by loading the given config file
# this has no effect besides defining variables and functions
# sets several global variables
load-config() {
    if [[ -n $CONFIG_FILE ]]; then
        return
    fi
    if [[ -z $DOCKER_RUNNING ]]; then
        CONFIG_FILE=${1:-input/config.sh}
    else
        CONFIG_FILE=${1:-_config.sh}
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo "Please provide a config file in $CONFIG_FILE."
        exit 1
    fi
    # shellcheck source=../input/config.sh
    source "$CONFIG_FILE"
    require-variable CONFIG_FILE INPUT_DIRECTORY OUTPUT_DIRECTORY SKIP_DOCKER_BUILD
}

# loads a config file and adds all experiment subjects
load-subjects() {
    load-config "$1"
    experiment-subjects
}

# removes all output files specified by the given config file, does not touch input files or Docker images
clean() {
    require-host
    load-config "$1"
    rm -rf "$OUTPUT_DIRECTORY"
}

# runs the experiment defined in the given config file
run() {
    require-host
    require-command docker
    load-config "$1"
    mkdir -p "$OUTPUT_DIRECTORY"
    rm -f "$(output-log main)" "$(output-err main)"
    experiment-stages
}

# stops a running experiment
stop() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^eval_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}
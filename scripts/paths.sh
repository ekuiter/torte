# returns the input directory
input-directory() {
    if [[ -z $docker_running ]]; then
        echo $input_directory
    else
        echo $docker_input_directory
    fi
}

# returns the directory for all outputs for a given stage
output-directory() {
    if [[ -z $docker_running ]]; then
        local stage=$1
        require-value stage
        echo $output_directory/$stage
    else
        echo $docker_output_directory
    fi
}

# returns a prefix for all output files for a given stage
output-prefix() {
    if [[ -z $docker_running ]]; then
        output-directory $1
    else
        echo $docker_output_directory/$docker_output_file_prefix
    fi
}

# returns a file with a given extension for the output of a given stage
output-file() {
    local extension=$1
    local stage=$2
    require-value extension
    echo $(output-prefix $stage).$extension
}

# standard output files
output-csv() { output-file csv $1; } # for experimental results
output-log() { output-file log $1; } # for human-readable output (by default, output of Docker container)
output-err() { output-file err $1; } # for human-readable errors

# moves all output files of a given stage into the root output directory
copy-output-files() {
    local stage=$1
    require-host
    require-value stage
    shopt -s nullglob
    for output_file in $(output-directory $stage)/$docker_output_file_prefix*; do
        local extension=${output_file#*.}
        cp $output_file $(output-file $extension $stage)
    done
    shopt -u nullglob
}
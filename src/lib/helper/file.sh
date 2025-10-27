#!/bin/bash
# file and directory helpers

# removes files and reports an error when there are permission issues
rm-safe(files...) {
    assert-array files
    LC_ALL=C rm -rf "${files[@]}" \
        2> >(grep -q "Permission denied" \
            && error "Could not remove ${files[*]} due to missing permissions, did you run Docker in rootless mode?")
}

# returns whether the given file if is empty
is-file-empty(file) {
    [[ ! -f "$file" ]] || [[ ! -s "$file" ]]
}

# removes the given file if it is empty
rm-if-empty(file) {
    if is-file-empty "$file"; then
        rm-safe "$file"
    fi
}

# silently push directory
push(directory) {
    pushd "$directory" > /dev/null || error "Failed to push directory $directory."
}

# silently pop directory
pop() {
    popd > /dev/null || error "Failed to pop directory."
}

# copies and renames files, including their revision
collect-files(from, to, extension, statistics_input=read-statistics, date_format=%Y%m%d%H%M%S_) {
    mkdir -p "$to"
    for f in $from; do
        # skip if the glob pattern didn't match any files
        [[ -f "$f" ]] || continue
        local revision
        local original_revision
        revision=$(basename "$f" ".$extension" | cut -d'[' -f1)
        original_revision=$(basename "$f" ".$extension" | cut -d'[' -f2 | cut -d']' -f1)
        cp "$f" "$to/$(date -d "@$(grep -E "^$revision," < "$(stage-directory "$statistics_input")"/"$OUTPUT_FILE_PREFIX".csv | cut -d, -f4)" +"$date_format")$original_revision.$extension"
    done
}

# copies and renames files from a given stage
# assumes the conventional structure of extraction and transformation stages
# conflates different systems into one directory, so this is best used with a single system
# to set the destination path, call collect-files directly
collect-stage-files(input, extension, statistics_input=read-statistics, date_format=%Y%m%d%H%M%S_) {
    collect-files \
            --from "$(follow-stage-directory "$input")"'/*/*.'"$extension" \
            --to "$STAGES_DIRECTORY/$extension${PASS:+"/$PASS"}" \
            --extension "$extension" \
            --statistics-input "$statistics_input" \
            --date-format "$date_format"
}

# atomically write a line to a file by locking an arbitrary constant file descriptor (200)
# useful when using parallel jobs to avoid garbled output
append-atomically(file, line) {
    {
        flock 200
        echo "$line" >&200
    } 200>>"$file"
}
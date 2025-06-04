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
#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment clones the original Linux git repository, then adds old revisions as tag, and rewrites its history to remove files with case-sensitive names.
# The resulting repository has been pushed as a fork to https://github.com/ekuiter/linux and is used as a default for most experiments to avoid checkout issues on macOS.
# There are only two reasons to avoid using this repository:
# 1) When very recent revisions should be analyzed (which the repository may not include yet).
# 2) When the original commit hashes are needed for a specific experiment (as they are rewritten). This restriction does not apply to tags, which are preserved.

TIMEOUT=10
LINUX_CLONE_MODE=filter

experiment-subjects() {
    add-linux-system
}

experiment-stages() {
    clone-systems
    tag-linux-revisions
}
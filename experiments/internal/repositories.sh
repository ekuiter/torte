#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment prepares all maintained repository forks in one place:
# 1) Linux is cloned from the original repository, old releases are added as tags, and history is rewritten to remove files with case-sensitive names.
#    The resulting repository has been pushed as a fork to https://github.com/ekuiter/torte-linux.
#    This fork is used by default to avoid checkout issues on macOS.
#    Avoid it only for very recent revisions that are not pushed yet, or when original Linux commit hashes are needed.
#    For successful local regeneration, this transform has to run on a case-sensitive file system.
# 2) BusyBox is cloned from the original repository, then KConfig files are generated for each revision that touches the feature model.
#    The resulting repository has been pushed as a fork to https://github.com/ekuiter/torte-busybox and is used as a default to improve performance.
#    This repository should only be avoided when very recent revisions should be analyzed (which the repository may not include yet).
# Run this experiment when the prepared forks should be refreshed, then execute repositories-push.sh to update the remotes.

CLONE_FORKS=
add-payload-file repositories-push.sh

experiment-systems() {
    add-linux-system
    add-busybox-kconfig-commits
}

experiment-stages() {
    clone-systems
    "$(payload-file repositories-push.sh)"
}

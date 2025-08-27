#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment clones the original BusyBox git repository and then generates KConfig files for each revision that touches the feature model.
# The resulting repository has been pushed as a fork to https://github.com/ekuiter/busybox and is used as a default to improved performance.
# This repository should only be avoided when very recent revisions should be analyzed (which the repository may not include yet).
# This is unlikely to be necessary because BusyBox is currently not being developed very actively.

BUSYBOX_GENERATE_MODE=generate

experiment-systems() {
    add-busybox-kconfig-history-commits
}

experiment-stages() {
    clone-systems
    generate-busybox-models

    # then execute manually:
    # cd stages/2_generate_busybox_models/busybox
    # git remote add origin git@github.com:ekuiter/busybox.git
    # git push origin master
}

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
# For successful execution, this experiment has to be run on a case-sensitive file system.

LINUX_CLONE_MODE=filter

experiment-systems() {
    add-linux-system
}

experiment-stages() {
    clone-systems
    tag-linux-revisions

    # then execute manually:
    # cd stages/1_clone_systems/linux
    # git remote add origin git@github.com:ekuiter/linux.git
    # git push --force origin master
    # git push --force origin --tags

    # the above may fail due to "remote: fatal: pack exceeds maximum allowed size (2.00 GiB)"
    # in that case, run the following to push in smaller batches (https://stackoverflow.com/q/15125862):
    # REMOTE=origin
    # BRANCH=$(git rev-parse --abbrev-ref HEAD)
    # BATCH_SIZE=20000

    # # check if the branch exists on the remote
    # if git show-ref --quiet --verify refs/remotes/$REMOTE/$BRANCH; then
    #     # if so, only push the commits that are not on the remote already
    #     range=$REMOTE/$BRANCH..HEAD
    # else
    #     # else push all the commits
    #     range=HEAD
    # fi
    # # count the number of commits to push
    # n=$(git log --first-parent --format=format:x $range | wc -l)

    # # push each batch
    # for i in $(seq $n -$BATCH_SIZE 1); do
    #     # get the hash of the commit to push
    #     h=$(git log --first-parent --reverse --format=format:%H --skip $i -n1)
    #     echo "Pushing $h..."
    #     git push --force $REMOTE ${h}:refs/heads/$BRANCH
    # done
    # # push the final partial batch
    # git push --force $REMOTE HEAD:refs/heads/$BRANCH
}
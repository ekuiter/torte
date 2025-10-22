#!/bin/bash

cd stages/1_clone_systems/linux
git remote add origin git@github.com:ekuiter/torte-linux.git
git checkout master

# push may fail due to "remote: fatal: pack exceeds maximum allowed size (2.00 GiB)"
# run the following to push in smaller batches (https://stackoverflow.com/q/15125862)
REMOTE=origin
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BATCH_SIZE=20000

# check if the branch exists on the remote
if git show-ref --quiet --verify refs/remotes/$REMOTE/$BRANCH; then
    # if so, only push the commits that are not on the remote already
    range=$REMOTE/$BRANCH..HEAD
else
    # else push all the commits
    range=HEAD
fi
# count the number of commits to push
n=$(git log --first-parent --format=format:x $range | wc -l)

# push each batch
for i in $(seq $n -$BATCH_SIZE 1); do
    # get the hash of the commit to push
    h=$(git log --first-parent --reverse --format=format:%H --skip $i -n1)
    echo "Pushing $h..."
    git push --force $REMOTE ${h}:refs/heads/$BRANCH
done
# push the final partial batch
git push --force $REMOTE HEAD:refs/heads/$BRANCH
git push --force --all origin
git push --force origin --tags
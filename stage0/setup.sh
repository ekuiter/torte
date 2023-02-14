#!/bin/bash

mkdir -p sloc
git config --global --add safe.directory '*'

git-checkout() (
    if [[ ! -d "input/$1" ]]; then
        echo "Cloning $1" | tee -a $LOG
        echo $2 $1
        git clone $2 input/$1
    fi
)

run() (
    if [[ $2 != skip-model ]]; then
        tag=$3
        unix=$(git -C input/$1 --no-pager log -1 -s --format=%ct $tag)
        (cd input/$1; cloc --git $tag > /home/sloc/$tag.txt)
        echo $1,$tag,$unix,$(date -d @$unix +"%Y-%m-%d"),$(cat sloc/$tag.txt | grep ^SUM | tr -s ' ' | cut -d' ' -f5)
    fi
)
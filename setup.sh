#!/bin/bash

NOT_IN_DOCKER=1

git-checkout() (
    if [[ ! -d "input/$1" ]]; then
        echo "Cloning $1" | tee -a $LOG
        echo $2 $1
        git clone $2 input/$1
    fi
)

run() (
    :
)
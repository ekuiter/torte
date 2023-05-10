#!/bin/bash

BIN_DIR=$(dirname $0)


echo "c o ================= SET PRIM INTRT HANDLING ==============="
function interrupted(){
    echo "c o Sending kill to subprocess"
    [ $TMP_OUT=="" ] && exit 42
    [ $TMP_OUT=="/" ] && exit 42
    [ $TMP_OUT=="~" ] && exit 42
    [ ! -z "$TMP_OUT" ] && rm -r $TMP_OUT
    kill -TERM $PID
    echo "c o Removing tmp files"
}

function finish {
  # Your cleanup code here
    [ $TMP_OUT=="" ] && exit 42
    [ $TMP_OUT=="/" ] && exit 42
    [ $TMP_OUT=="~" ] && exit 42
    [ ! -z "$TMP_OUT" ] && rm -r $TMP_OUT
    echo "c o Removing tmp files"
}
trap finish EXIT
trap interrupted TERM
trap interrupted INT

TMP_OUT=$(mktemp -d)


#${BIN_DIR}/TwG2 --timeout=$STAREXEC_WALLCLOCK_LIMIT --tmpdir=${TMP_OUT} $1
"$(dirname "$0")"/TwG "--tmpdir=$TMP_OUT" "$1"
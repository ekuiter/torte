#!/bin/bash

if [ "x$1" = "x" ]; then
  echo "USAGE: SatELiteGTI <input CNF>"
  exit 1
fi

if [ -L $0 ]; then
  XDIR=`ls -l --color=no $0 | sed "s%.*-> \(.*\)/.*$%\1%"`
else
  XDIR=`echo $0 | sed "s%\(.*\)/.*$%\1%"`
fi

TMP=/tmp/solver34-tmp-$$
SE=$XDIR/05-SatELite
MS=$XDIR/05-MiniSat 
if [ x"$1" = "xdebug" ]; then SE=$XDIR/SatELite; shift;fi   
INPUT=$1; shift

$SE "$@" $INPUT $TMP.bcnf $TMP.vmap $TMP.elim
X=$?
if [ $X == 0 ]; then
  $MS $TMP.bcnf $TMP.result
  X=$?
  if [ $X == 20 ]; then
    echo "s UNSATISFIABLE"
    rm -f $TMP.bcnf $TMP.vmap $TMP.elim $TMP.result
    exit 20
  elif [ $X != 10 ]; then
    rm -f $TMP.bcnf $TMP.vmap $TMP.elim $TMP.result
    exit $X
  fi  

  $SE +ext $INPUT $TMP.result $TMP.vmap $TMP.elim
  X=$?
fi    

rm -f $TMP.bcnf $TMP.vmap $TMP.elim $TMP.result
exit $X

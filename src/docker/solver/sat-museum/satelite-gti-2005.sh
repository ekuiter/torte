#!/bin/sh

if [ "x$1" = "x" ]; then
  echo "USAGE: SatELiteGTI <input CNF>"
  exit 1
fi

if [ -L $0 ]; then
  XDIR=`ls -l --color=no $0 | sed "s%.*-> \(.*\)/.*$%\1%"`
else
  XDIR=`echo $0 | sed "s%\(.*\)/.*$%\1%"`
fi

TMP="$(mktemp -d)"/GTI_${HOSTNAME}_$$
SE=$XDIR/satelite-2005
MS=$XDIR/minisat-2005
if [ x"$1" = "xdebug" ]; then SE=$XDIR/SatELite; shift;fi   
INPUT=$1; shift

cleanup () {
  echo rm -f $TMP.bcnf $TMP.vmap $TMP.elim $TMP.result
}

trap "cleanup" 2 3 9 15

echo c $SE "$@" $INPUT $TMP.bcnf $TMP.vmap $TMP.elim
$SE "$@" $INPUT $TMP.bcnf $TMP.vmap $TMP.elim
X=$?
if [ $X = 0 ]; then
  echo c $MS $TMP.bcnf $TMP.result
  $MS $TMP.bcnf $TMP.result
  X=$?
  if [ $X = 20 ]; then
    echo "s UNSATISFIABLE"
    cleanup
    exit 20
  elif [ ! $X = 10 ]; then
    cleanup
    exit $X
  fi  

  echo c $SE +ext $INPUT $TMP.result $TMP.vmap $TMP.elim
  $SE +ext $INPUT $TMP.result $TMP.vmap $TMP.elim
  X=$?
fi    

cleanup
exit $X

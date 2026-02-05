#!/bin/bash

if [ "x$1" = "x" ]; then
  echo "USAGE: SatELiteGTI <input CNF>"
  exit 1
fi

TMP="$(mktemp -d)"/SatElite_temp
SE=$(dirname "$0")/07-SatELite
RS=$(dirname "$0")/07-RSat
INPUT=$1; shift 

$SE $INPUT $TMP.cnf $TMP.vmap $TMP.elim
X=$?
if [ $X == 0 ]; then
  #SatElite terminated correctly
  $RS $TMP.cnf -r $TMP.result #"$@"
  X=$?
  if [ $X == 20 ]; then
    #RSat must not print out result!
    echo "s UNSATISFIABLE"
    rm -f $TMP.cnf $TMP.vmap $TMP.elim $TMP.result
    exit 20
    #Don't call SatElite for model extension.
  elif [ $X != 10 ]; then
    #timeout/unknown, nothing to do, just clean up and exit.
    rm -f $TMP.cnf $TMP.vmap $TMP.elim $TMP.result
    exit $X
  fi  

  #SATISFIABLE, call SatElite for model extension
  $SE +ext $INPUT $TMP.result $TMP.vmap $TMP.elim
  X=$?
elif [ $X == 11 ]; then
  #SatElite died, RSat must take care of the rest
  $RS $INPUT -s #"$@"#but we must force rsat to print out result here!!!
  X=$?
fi    

rm -f $TMP.cnf $TMP.vmap $TMP.elim $TMP.result
exit $X

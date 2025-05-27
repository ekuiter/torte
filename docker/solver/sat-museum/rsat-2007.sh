#!/bin/sh

if [ "x$1" = "x" ]; then
  echo "USAGE: SatELiteGTI <input CNF>"
  exit 1
fi

TMP=/tmp/rsat-$$
SE=`echo $0|xargs dirname`/satelite-2007
RS=`echo $0|xargs dirname`/rsat-2007
INPUT="$1"

cleanup () {
rm -f $TMP.cnf $TMP.vmap $TMP.elim $TMP.result
}

trap "cleanup" 2 3 9 15

$SE "$INPUT" $TMP.cnf $TMP.vmap $TMP.elim
X=$?
if [ $X = 0 ]; then
  #SatElite terminated correctly
  $RS $TMP.cnf -r $TMP.result #"$@"
  X=$?
  if [ $X = 20 ]; then
    #RSat must not print out result!
    echo "s UNSATISFIABLE"
    cleanup
    exit 20
    #Don't call SatElite for model extension.
  elif [ ! $X = 10 ]; then
    #timeout/unknown, nothing to do, just clean up and exit.
    cleanup
    exit $X
  fi  
  
  #SATISFIABLE, call SatElite for model extension
  $SE +ext "$INPUT" $TMP.result $TMP.vmap $TMP.elim
  X=$?
elif [ $X = 11 ]; then
  #SatElite died, RSat must take care of the rest
  $RS "$INPUT" -s #"$@"#but we must force rsat to print out result here!!!
  X=$?
fi    

cleanup
exit $X

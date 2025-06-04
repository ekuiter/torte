#!/bin/sh
`dirname $0`/berkmin-2003 $* | \
awk '$1 == "solution" {
  printf "v"
  for (i = 3; i <= NF; i++)
    printf " " $i
  print " 0"
  next
}
$1 == "Satisfiable" { res=10; print "s SATISFIABLE"; next}
$1 == "UNSATISFIABLE" { res=20; print "s UNSATISFIABLE"; next}
{ print "c", $0 }
END { exit res }'

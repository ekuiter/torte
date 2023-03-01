#!/bin/bash
log=run.log
rm -rf $log
touch $log

competition-format() {
    mc_int=$(cat $log | grep "c s exact .* int" | cut -d' ' -f6)
    mc_double=$(cat $log | grep "c s exact double prec-sci" | cut -d' ' -f6)
    mc_log10=$(cat $log | grep "c s log10-estimate" | cut -d' ' -f4)
}

c2d() {
    (cd c2d/bin; bash starexec_run_default ../../$1) > $log
    competition-format
}

d4() {
    (cd d4/bin; bash starexec_run_default.sh ../../$1) > $log
    competition-format
}

dpmc() {
    (cd dpmcpre/bin; bash starexec_run_1pre1mp1 ../../$1) > $log
    competition-format
}

gpmc() {
    (cd gpmc/bin; bash starexec_run_track1 ../../$1) > $log
    competition-format
}

# todo: dunno which configuration is the right one ...
sharpsat-td-arjun1() {
    (cd Narsimha-track1v-7112ef8eb466e9475/bin; bash starexec_run_track1_conf1.sh ../../$1) > $log
    competition-format
}

sharpsat-td-arjun2() {
    (cd Narsimha-track1v-7112ef8eb466e9475/bin; bash starexec_run_track1_conf2.sh ../../$1) > $log
    competition-format
}

sharpsat-td() { # todo: timeout, maxrss, does not seem to work
	(cd SharpSAT-TD-unweighted/bin; bash starexec_run_default ../../$1) > $log
	competition-format
}

twg() { # may have small precision loss, which twg1/2 is the right one?
    (cd TwG/bin; bash starexec_run_1.sh ../../$1) > $log
    competition-format
}

# todo: other ase solvers, parse result format
ase22-countantom() {
    ase22/countAntom $1 > $log
}

#result=$(cat $log | sed -z 's/\n# solutions \n/SHARPSAT/g' | grep -oP "((?<=Counting...)\d+(?= models)|(?<=  Counting...)\d+(?= models)|(?<=c model count\.{12}:)\d+|(?<=^s)\d+|(?<=^s mc)\d+|(?<=#SAT \(full\):   		)\d+|(?<=SHARPSAT)\d+|(?<=Number of solutions\t\t\t)[.e+\-\d]+)" || true)

# MTMC?
# ExactMC?

$@
echo mc_int=$mc_int
echo mc_double=$mc_double
echo mc_log10=$mc_log10
cat $log
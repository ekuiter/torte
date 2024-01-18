#!/bin/bash
if [[ -f "$1" ]]; then
    cnf=$(mktemp --suffix .cnf)
    cp "$1" "$cnf"
    java -jar SATGraf/build/libs/SATGraf-1.0-SNAPSHOT-all.jar exp -f "$cnf" -o "$2"
    rm "$cnf"
fi
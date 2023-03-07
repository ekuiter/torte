#! /bin/bash
# todo: update to new featjar version
# shellcheck source=../../scripts/torte.sh
source torte.sh load-config
cd /home/spldev/evaluation-cnf
table-field "$(input-csv)" kconfig-model > config/models.txt
sed -i "s/TRANSFORM_INTO_CNF_TIMEOUT/$TRANSFORM_INTO_CNF_TIMEOUT/" config/config.properties
JAR=evaluation-cnf-1.0-SNAPSHOT-combined.jar
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:libraries/ java -da -Xmx12g -cp "$JAR:libraries/*" org.spldev.util.cli.CLI extract-cnf config

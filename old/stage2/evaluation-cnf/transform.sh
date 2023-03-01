#! /bin/bash
cd "$(dirname "$0")"
cp output/models.txt config/
sed -i "s/TIMEOUT_TRANSFORM/$TIMEOUT_TRANSFORM/" config/config.properties
JAR=evaluation-cnf-1.0-SNAPSHOT-combined.jar
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:libraries/ java -da -Xmx12g -cp "$JAR:libraries/*" org.spldev.util.cli.CLI extract-cnf config

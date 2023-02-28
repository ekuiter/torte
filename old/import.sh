#!/bin/bash
set -e
CONTAINERS=(stage1_kconfigreader stage1_kclause stage2 stage3)

for container in ${CONTAINERS[@]}; do
    docker load -i $container.tar.gz
done
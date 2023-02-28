#!/bin/bash
set -e
CONTAINERS=(stage1_kconfigreader stage1_kclause stage2 stage3)

docker build -f stage1/kconfigreader/Dockerfile -t stage1_kconfigreader stage1
docker build -f stage1/kclause/Dockerfile -t stage1_kclause stage1
docker build -f stage2/Dockerfile -t stage2 stage2
docker build -f stage3/Dockerfile -t stage3 stage3

mkdir -p export

for container in ${CONTAINERS[@]}; do
    docker save $container | gzip > export/$container.tar.gz
done

cp -R *.sh *.R output input export/
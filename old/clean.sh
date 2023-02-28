#!/bin/bash
rm -rf output
docker rm -f stage1_kconfigreader stage1_kclause stage2 stage3 || true
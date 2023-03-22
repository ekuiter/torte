#!/bin/bash
# ./extract-kconfig-models.sh
# compiles kconfig bindings and extracts kconfig models using kclause

load-config
register-kconfig-extractor kclause kextractor
load-subjects
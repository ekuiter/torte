#!/bin/bash
if [[ $# -ne 1 ]]; then
    echo "Illegal number of parameters."
    echo "Usage: copy_files.sh \$KERNEL_SOURCE_TREE"
    exit 1
fi

cp -r ./scripts/kconfig $1/scripts
echo "Files copied successfully. Now run 'make xconfig' in $1"
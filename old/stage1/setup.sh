#!/bin/bash

if [[ -d "kconfigreader" ]]; then
    READER=kconfigreader
elif [[ -d "kmax" ]]; then
    READER=kclause
else
    echo "no reader found, please run script inside of Docker"
    exit 1
fi
LOG=/home/output/log_$READER.txt
MODELS=/home/output/models_$READER.csv
if [ $READER = kconfigreader ]; then
    BINDING=dumpconf
elif [ $READER = kclause ]; then
    BINDING=kextractor
else
    echo "invalid reader"
    exit 1
fi
BINDING_ENUMS=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ dir_dep)

cd /home
mkdir -p output
echo -n > $LOG
echo -n > $MODELS
echo system,tag,c-binding,kconfig-file >> $MODELS
git config --global --add safe.directory "*"

# compiles the C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against the Kconfig parser, respectively
c-binding() (
    if [ $2 = buildroot ]; then
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \; # ignore generated Kconfig files in buildroot
    fi
    set -e
    mkdir -p /home/output/c-bindings/$2
    args=""
    binding_files=$(echo $4 | tr , ' ')
    binding_dir=$(dirname $binding_files | head -n1)
    for enum in ${BINDING_ENUMS[@]}; do
        if grep -qrnw $binding_dir -e $enum; then
            args="$args -DENUM_$enum"
        fi
    done
    # make sure all dependencies for the C program are compiled
    # make config sometimes asks for integers (not easily simulated with "yes"), which is why we add a timeout
    make $binding_files >/dev/null || (yes | make allyesconfig >/dev/null) || (yes | make xconfig >/dev/null) || (yes "" | timeout 20s make config >/dev/null) || true
    strip -N main $binding_dir/*.o || true
    cmd="gcc /home/$1.c $binding_files -I $binding_dir -Wall -Werror=switch $args -Wno-format -o /home/output/c-bindings/$2/$3.$1"
    (echo $cmd >> $LOG) && eval $cmd
)

read-model() (
    # read-model kconfigreader|kclause system commit c-binding Kconfig env
    set -e
    mkdir -p /home/output/models/$2
    if [ -z "$6" ]; then
        env=""
    else
        env="$(echo '' -e $6 | sed 's/,/ -e /g')"
    fi
    # the following hacks may impair accuracy, but are necessary to extract a model
    if [ $2 = freetz-ng ]; then
        touch make/Config.in.generated make/external.in.generated config/custom.in # ugly hack because freetz-ng is weird
    fi
    if [ $2 = buildroot ]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus .br2-external.in.skeleton .br2-external.in.init
    fi
    if [ $2 = toybox ]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
    if [ $2 = linux ]; then
        # ignore all constraints that use the newer $(success,...) syntax
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*default $(.*//g' {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*depends on $(.*//g' {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*def_bool $(.*//g' {} \;
        # ugly hack for linux 6.0
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*def_bool ((.*//g' {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*//g' {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i 's/\s*$(as-instr,endbr64).*//g' {} \;
    fi
    i=0
    while [ $i -ne $N ]; do
        i=$(($i+1))
        model="/home/output/models/$2/$3,$i,$1.model"
        if [ $1 = kconfigreader ]; then
            start=`date +%s.%N`
            cmd="/home/kconfigreader/run.sh de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf $4 $5 /home/output/models/$2/$3,$i,$1"
            (echo $cmd | tee -a $LOG) && eval $cmd
            end=`date +%s.%N`
        elif [ $1 = kclause ]; then
            start=`date +%s.%N`
            cmd="$4 --extract -o /home/output/models/$2/$3,$i,$1.kclause $env $5"
            (echo $cmd | tee -a $LOG) && eval $cmd
            cmd="$4 --configs $env $5 > /home/output/models/$2/$3,$i,$1.features"
            (echo $cmd | tee -a $LOG) && eval $cmd
            if [ $2 = embtoolkit ]; then
                # fix incorrect feature names, which Kclause interprets as a binary subtraction operator
                sed -i 's/-/_/g' /home/output/models/$2/$3,$i,$1.kclause
            fi
            cmd="kclause < /home/output/models/$2/$3,$i,$1.kclause > $model"
            (echo $cmd | tee -a $LOG) && eval $cmd
            end=`date +%s.%N`
            cmd="python3 /home/kclause2kconfigreader.py $model > $model.tmp && mv $model.tmp $model"
            (echo $cmd | tee -a $LOG) && eval $cmd
        fi
        echo "#item time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> $model
    done
)

git-checkout() (
    if [[ ! -d "input/$1" ]]; then
        echo "Cloning $1" | tee -a $LOG
        echo $2 $1
        git clone $2 input/$1
    fi
    if [ ! -z "$3" ]; then
        cd input/$1
        git reset --hard
        git clean -dfx
        git checkout -f $3
    fi
)

run() (
    set -e
    echo | tee -a $LOG
    if ! echo $4 | grep -q c-bindings; then
        binding_path=/home/output/c-bindings/$1/$3.$BINDING
    else
        binding_path=$4
    fi
    if [[ ! -f "/home/output/models/$1/$3.$READER.model" ]]; then
        trap 'ec=$?; (( ec != 0 )) && (rm -f /home/output/models/'$1'/'$3',*,'$READER'* && echo FAIL | tee -a $LOG) || (echo SUCCESS | tee -a $LOG)' EXIT
        if [[ $2 != skip-checkout ]]; then
            echo "Checking out $3 in $1" | tee -a $LOG
            eval git-checkout $1 $2 $3
        fi
        cd input/$1
        if [ ! $binding_path = "$4" ]; then
            echo "Compiling C binding $BINDING for $1 at $3" | tee -a $LOG
            c-binding $BINDING $1 $3 $4
        fi
        if [[ $2 != skip-model ]]; then
            echo "Reading feature model for $1 at $3" | tee -a $LOG
            read-model $READER $1 $3 $binding_path $5 $6
        fi
        cd /home
    else
        echo "Skipping feature model for $1 at $3" | tee -a $LOG
    fi
    echo $1,$3,$binding_path,$5 >> $MODELS
)
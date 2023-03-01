# compiles a C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against the Kconfig parser, respectively
compile-c-binding() (
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep)
    local c_binding=$1
    local system=$2
    local revision=$3
    local c_binding_files=$4
    require-value c_binding system revision c_binding_files
    # todo: move system-specific hacks somewhere else
    if [[ $system == buildroot ]]; then
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \; # ignore generated Kconfig files in buildroot
    fi
    mkdir -p $docker_output_directory/$c_bindings_output_directory/$system
    pushd $(input-directory)/$system

    # determine which Kconfig constructs this system uses
    local gcc_arguments=""
    local c_binding_files=$(echo $c_binding_files | tr , ' ')
    local c_binding_directory=$(dirname $c_binding_files | head -n1)
    for construct in ${kconfig_constructs[@]}; do
        if grep -qrnw $c_binding_directory -e $construct 2>/dev/null; then
            gcc_arguments="$gcc_arguments -DENUM_$construct"
        fi
    done

    # make sure all dependencies for the C program are compiled
    # make config sometimes asks for integers (not easily simulated with "yes"), which is why we add a timeout
    make $c_binding_files >/dev/null || (yes | make allyesconfig >/dev/null) || (yes | make xconfig >/dev/null) || (yes "" | timeout 20s make config >/dev/null) || true
    strip -N main $c_binding_directory/*.o || true
    local cmd="gcc ../../$c_binding.c $c_binding_files -I $c_binding_directory -Wall -Werror=switch $gcc_arguments -Wno-format -o $docker_output_directory/$c_bindings_output_directory/$system/$revision.$c_binding"
    echo $cmd
    eval $cmd || true
    # todo: clean git?
    popd
)

# todo
extract-kconfig-model() (
    set -e
    mkdir -p $docker_output_directory/$models_output_directory/$2
    if [ -z "$6" ]; then
        env=""
    else
        env="$(echo '' -e $6 | sed 's/,/ -e /g')"
    fi
    # todo: move hacks to other file
    # the following hacks may impair accuracy, but are necessary to extract a kconfig model
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
        local model="$docker_output_directory/$models_output_directory/$2/$3,$i,$1.model"
        if [ $1 = kconfigreader ]; then
            start=`date +%s.%N`
            cmd="/home/kconfigreader/run.sh de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf $4 $5 $docker_output_directory/$models_output_directory/$2/$3,$i,$1"
            (echo $cmd | tee -a $LOG) && eval $cmd
            end=`date +%s.%N`
        elif [ $1 = kclause ]; then
            start=`date +%s.%N`
            cmd="$4 --extract -o $docker_output_directory/$models_output_directory/$2/$3,$i,$1.kclause $env $5"
            (echo $cmd | tee -a $LOG) && eval $cmd
            cmd="$4 --configs $env $5 > $docker_output_directory/$models_output_directory/$2/$3,$i,$1.features"
            (echo $cmd | tee -a $LOG) && eval $cmd
            if [ $2 = embtoolkit ]; then
                # fix incorrect feature names, which Kclause interprets as a binary subtraction operator
                sed -i 's/-/_/g' $docker_output_directory/$models_output_directory/$2/$3,$i,$1.kclause
            fi
            cmd="kclause < $docker_output_directory/$models_output_directory/$2/$3,$i,$1.kclause > $model"
            (echo $cmd | tee -a $LOG) && eval $cmd
            end=`date +%s.%N`
            cmd="python3 /home/kclause2kconfigreader.py $model > $model.tmp && mv $model.tmp $model"
            (echo $cmd | tee -a $LOG) && eval $cmd
        fi
        echo "#item time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> $model
    done
)

# todo
compile-c-binding-and-extract-kconfig-model() {
    local extractor=$1
    local c_binding=$2
    local system=$3
    local revision=$4
    local c_binding_files=$5
    local kconfig_file=$6
    local env=$7
    require-value system revision c_binding_files kconfig_file
    if ! echo $c_binding_files | grep -q $c_bindings_output_directory; then
        local binding_path=$docker_output_directory/$c_bindings_output_directory/$system/$revision.$c_binding
    else
        local binding_path=$c_binding_files
    fi
    if [[ ! -f $docker_output_directory/$models_output_directory/$system/$revision,*,$extractor.model ]]; then
        trap 'ec=$?; (( ec != 0 )) && (rm -f '$docker_output_directory/$models_output_directory/$system/$revision',*,'$extractor'* && echo FAIL) || (echo SUCCESS)' EXIT
        if [[ $system != skip-checkout ]]; then
            echo "Checking out $revision in $system"
            git-checkout $revision $(input-directory)/$system
        fi
        pushd $(input-directory)/$system
        if [[ $binding_path != "$c_binding_files" ]]; then
            echo "Compiling C binding $c_binding for $system at $revision"
            compile-c-binding $c_binding $system $revision $c_binding_files
        fi
        # if [[ $2 != skip-model ]]; then
        #     echo "Reading feature model for $system at $revision"
        #     extract-model $extractor $system $revision $binding_path $5 $6
        # fi
        popd
    else
        echo "Skipping Kconfig model for $system at $revision"
    fi
    echo $system,$revision,$binding_path,$kconfig_file >> $(output-csv)
}
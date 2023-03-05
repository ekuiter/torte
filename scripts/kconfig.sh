#!/bin/bash

# checks out a subject and prepares it for further processing
kconfig-checkout() {
    local system=$1
    local revision=$2
    local kconfig_binding_files_spec=$3
    require-value system revision
    local kconfig_binding_files
    kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
    local kconfig_binding_directory
    kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
    push "$(input-directory)/$system"
    git-checkout "$revision" "$PWD"
    kconfig-post-checkout-hook "$system" "$revision"
    if [[ -n $kconfig_binding_files_spec ]]; then
        # make sure all dependencies for the kconfig binding are compiled
        # make config sometimes asks for integers (not easily simulated with "yes"), which is why we add a timeout
        make "$kconfig_binding_files" >/dev/null \
            || (yes | make allyesconfig >/dev/null) \
            || (yes | make xconfig >/dev/null) \
            || (yes "" | timeout 20s make config >/dev/null) \
            || true
        strip -N main "$kconfig_binding_directory"/*.o || true
    fi
    pop
}

# returns all files needed to compile a kconfig binding
kconfig-binding-files() {
    kconfig_binding_files_spec=$1
    require-value kconfig_binding_files_spec
    echo "$kconfig_binding_files_spec" | tr , ' '
}

# returns the directory containing the kconfig binding files
kconfig-binding-directory() {
    kconfig_binding_files_spec=$1
    require-value kconfig_binding_files_spec
    dirname "$(kconfig-binding-files "$kconfig_binding_files_spec")" | head -n1
}

# compiles a C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against the Kconfig parser, respectively
compile-kconfig-binding() {
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep)
    local kconfig_binding_name=$1
    local system=$2
    local revision=$3
    local kconfig_binding_files_spec=$4
    require-value kconfig_binding_name system revision kconfig_binding_files_spec
    local kconfig_binding_files
    kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
    local kconfig_binding_directory
    kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
    local kconfig_binding_output_file
    kconfig_binding_output_file=$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system/$revision.$kconfig_binding_name
    if [[ -f $kconfig_binding_output_file ]]; then
        echo "Skipping Kconfig binding $kconfig_binding_name for $system at $revision"
        return
    fi
    echo "Compiling Kconfig binding $kconfig_binding_name for $system at $revision"
    mkdir -p "$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system"
    push "$(input-directory)/$system"

    # determine which Kconfig constructs this system uses
    local gcc_arguments=""
    for construct in "${kconfig_constructs[@]}"; do
        if grep -qrnw "$kconfig_binding_directory" -e "$construct" 2>/dev/null; then
            gcc_arguments="$gcc_arguments -DENUM_$construct"
        fi
    done

    local cmd="gcc ../../$kconfig_binding_name.c $kconfig_binding_files -I $kconfig_binding_directory -Wall -Werror=switch $gcc_arguments -Wno-format -o $kconfig_binding_output_file"
    (echo "$cmd" && eval "$cmd") || true
    chmod +x "$kconfig_binding_output_file" || true
    pop
    if [[ ! -f $kconfig_binding_output_file ]]; then
        echo "Failed to compile Kconfig binding $kconfig_binding_name for $system at $revision" 1>&2
        return
    fi

    # todo: return binding file, then pass it to extract-kconfig-model
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model() {
    local extractor=$1
    local kconfig_binding=$2
    local system=$3
    local revision=$4
    local kconfig_binding_file=$5
    local kconfig_file=$6
    local env=$7
    require-value extractor kconfig_binding system revision kconfig_file
    for file in "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,"*",$extractor.model"; do
        if [[ -f $file ]]; then
            echo "Skipping Kconfig model for $system at $revision"
            return
        fi
    done
    echo "Reading feature model for $system at $revision"
    trap 'ec=$?; (( ec != 0 )) && (rm -f '"$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision"',*,'"$extractor"'* && echo FAIL) || (echo SUCCESS)' EXIT # todo remove this?
    mkdir -p "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system"
    push "$(input-directory)/$system"
    if [[ -z $kconfig_binding_file ]]; then
        kconfig_binding_file=$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system/$revision.$kconfig_binding
    fi
    if [[ -n $env ]]; then
        env="$(echo '' -e "$6" | sed 's/,/ -e /g')"
    fi
    i=0
    local N=1 # todo: iterations
    while [[ $i -ne $N ]]; do
        i=$((i+1))
        local model
        model="$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor.model"
        if [[ $extractor == kconfigreader ]]; then
            start=$(date +%s.%N)
            cmd="/home/kconfigreader/run.sh de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf $kconfig_binding_file $kconfig_file $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor"
            (echo "$cmd" && eval "$cmd") || true
            end=$(date +%s.%N)
        elif [[ $extractor == kclause ]]; then
            start=$(date +%s.%N)
            cmd="$kconfig_binding_file --extract -o $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor.kclause $env $kconfig_file"
            (echo "$cmd" && eval "$cmd") || true
            cmd="$kconfig_binding_file --configs $env $kconfig_file > $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor.features"
            (echo "$cmd" && eval "$cmd") || true
            if [[ $extractor == embtoolkit ]]; then
                # fix incorrect feature names, which Kclause interprets as a binary subtraction operator
                sed -i 's/-/_/g' "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor.kclause"
            fi
            cmd="kclause < $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision,$i,$extractor.kclause > $model"
            (echo "$cmd" && eval "$cmd") || true
            end=$(date +%s.%N)
            cmd="python3 /home/kclause2kconfigreader.py $model > $model.tmp && mv $model.tmp $model"
            (echo "$cmd" && eval "$cmd") || true
        fi
        echo "#item time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> "$model"
    done
    pop
    echo "$system,$revision,$kconfig_binding_file,$kconfig_file" >> "$(output-csv)"
    # todo: improve output, improve error log
}
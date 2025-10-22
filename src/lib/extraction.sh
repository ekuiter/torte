#!/bin/bash
# extracts kconfig models by adapting (variations of) LKC, the Linux kernel configurator

LKC_BINDINGS_DIRECTORY=lkc-bindings # output directory for storing LKC bindings

# checks out a system and prepares it for further processing
kconfig-checkout(system, revision) {
    log "git: $system@$revision" "$(echo-progress checkout)"
    local revision_clean err
    revision_clean=$(clean-revision "$revision")
    push "$(input-directory)/$system"
    git-checkout "$revision_clean"
    # run system-specific code that may impair accuracy, but is necessary to extract a kconfig model
    compile-hook kconfig-post-checkout-hook
    kconfig-post-checkout-hook "$system" "$revision"
    pop
    log "" "$(echo-done)"
}

# compiles a C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against LKC's Kconfig parser, respectively
# lkc_directory must contain an implementation of LKC with a conf.c file, which we replace with the custom implementation given by the binding name
compile-lkc-binding(lkc_binding, system, revision, lkc_directory, lkc_target=config, lkc_output_directory=, environment=) {
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep sym_is_optional sym_get_choice_prop)
    revision=$(clean-revision "$revision")
    local lkc_binding_output_file
    lkc_binding_output_file="$(output-path "$LKC_BINDINGS_DIRECTORY" "$system" "$revision.$lkc_binding")"
    log "$lkc_binding: $system@$revision"
    if [[ -f $lkc_binding_output_file ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress compile)"
    push "$(input-directory)/$system"

    # explicitly expand possible wildcards in lkc_directory, which is necessary for systems that have a dynamic LKC path
    # shellcheck disable=SC2116 disable=SC2086
    lkc_directory=$(echo $lkc_directory)
    lkc_output_directory=${lkc_output_directory:-$lkc_directory}

    # override the default configurator with our own implementation, which just dumps all the configuration options and their dependencies for the extractor
    mkdir -p "$lkc_directory"
    cp "/home/$lkc_binding.c" "$lkc_directory/conf.c"

    # determine which Kconfig constructs this system uses and enable them in our implementation
    local kconfig_construct
    for kconfig_construct in "${kconfig_constructs[@]}"; do
        if grep -qrnw "$lkc_directory" --exclude=conf.c -e "$kconfig_construct" 2>/dev/null; then
            sed -i "s/HAS_$kconfig_construct/1/" "$lkc_directory/conf.c"
        fi
    done

    # run system-specific code for influencing the binding compilation, if needed
    compile-hook kconfig-pre-binding-hook
    for macro in $(kconfig-pre-binding-hook "$system" "$revision" "$lkc_directory"); do
        sed -i "s/$macro/1/" "$lkc_directory/conf.c"
    done

    # this is the tricky part where we compile the binding
    # this differs from system to system, but most systems have a target like config, allyesconfig, ... which we can hijack
    # the trick is that we're not interested in running any of these tools - we just want their dependency "conf.c" to be compiled
    # this way we avoid building up a complex gcc build command, which is not flexible enough to account for all systems
    set-environment "$environment"
    if true; then # false for debugging
        yes "" | make "$lkc_target" >/dev/null 2>&1 || true
    else
        yes "" | make "$lkc_target" 1>&2
        error
    fi
    unset-environment "$environment"

    # compilation done, we now have a binary file that can dump configuration options and their dependencies
    if [[ -f $lkc_output_directory/conf ]]; then
        cp "$lkc_output_directory/conf" "$lkc_binding_output_file"
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        lkc_binding_output_file=NA
    fi
    pop
    echo "$system,$revision,$lkc_binding_output_file" >> "$(output-path lkc-bindings.csv)"
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model(extractor, lkc_binding=, system, revision, kconfig_file, lkc_binding_file=, environment=, timeout=0) {
    local revision_clean
    revision_clean=$(clean-revision "$revision")
    local architecture
    architecture=$(get-architecture "$revision")
    if [[ -z "$lkc_binding" ]]; then
        lkc_binding_file=""
    else
        lkc_binding_file=${lkc_binding_file:-$(output-path "$LKC_BINDINGS_DIRECTORY" "$system" "$revision_clean")}
        lkc_binding_file+=.$lkc_binding
    fi
    log "$extractor: $system@$revision"
    local file_extension="model"
    if [[ $extractor == configfix ]]; then
        file_extension="model"
    fi
    if [[ -f $(output-path "$system" "$revision.model") ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress extract)"
    trap 'ec=$?; (( ec != 0 )) && rm-safe '"$(output-path "$system" "$revision")"'*' EXIT
    push "$(input-directory)/$system"
    local kconfig_model
    kconfig_model=$(output-path "$system" "$revision.model")
    local features_file
    features_file=$(output-path "$system" "$revision.features")
    local output_log
    output_log=$(mktemp)
    if [[ -f $kconfig_file ]]; then
        # todo ConfigFix: maybe create a dummy binding file for ConfigFix, so to avoid this parameter getting optional? (could just revert part of the change from the merge commit)
        if [[ -z "$lkc_binding_file" || -f $lkc_binding_file ]]; then
            set-environment "$environment"
            if [[ $extractor == kconfigreader ]]; then
                measure "$timeout" /home/kconfigreader/run.sh \
                    "$(memory-limit 1)" \
                    de.fosd.typechef.kconfig.KConfigReader \
                    --fast \
                    --dumpconf "$lkc_binding_file" \
                    "$kconfig_file" \
                    "$(output-path "$system" "$revision")" \
                    | tee "$output_log"
                local time
                time=$(grep -oP "^measure_time=\K.*" < "$output_log")
            elif [[ $extractor == kclause ]]; then
                measure "$timeout" /home/kextractor.sh \
                    "$lkc_binding_file" \
                    "$(output-path "$system" "$revision.kextractor")" \
                    "$features_file" "$kconfig_file" \
                    | tee "$output_log"
                time=$(grep -oP "^measure_time=\K.*" < "$output_log")
                compile-hook kclause-post-binding-hook
                kclause-post-binding-hook "$system" "$revision"
                measure "$timeout" /home/kclause.sh \
                    "$(output-path "$system" "$revision.kextractor")" \
                    "$(output-path "$system" "$revision.kclause")" \
                    "$kconfig_model" \
                    | tee "$output_log"
                time=$((time+$(grep -oP "^measure_time=\K.*" < "$output_log")))
            elif [[ $extractor == configfix ]]; then
                linux_source="/home/linux/linux-6.10"
                export KBUILD_KCONFIG=$(realpath "$kconfig_file")
                export srctree="/home/input/$system"
                #todo ConfigFix: check these preprocessings and move them into hooks should they be necessary
                #preprocessing for system busybox
                if [[ "$system" == "busybox" ]]; then
                    find "$srctree" -type f -exec sed -i '/source\s\+networking\/udhcp\/Config\.in/d' {} \;
                    find $srctree -name "$kconfig_file" -exec sed -i -r '/^source "[^"]+"/! s|^source (.*)$|source "/home/input/'"$system"'/\1"|' {} \;
                fi
                #preprocessing for system axtls
                if [[ "$system" == "axtls" ]]; then
                    find "$srctree" -type f -name "Config.in" -exec sed -i -r '/^source "[^"]+"/! s|^source (.*)$|source "/home/input/'"$system"'/\1"|' {} \;
                fi
                #preprocessing for system uclibc-ng
                if [[ "$system" == "uclibc-ng" ]]; then
                    find "$srctree" -type f -exec sed -i -r "s|^source\\s+\"(.*)\"|source \"$(realpath "$srctree")/\\1\"|" {} \;
                    # to ask 
                    find "$srctree" -type f -exec sed -i '/option env/d' {} \;
                fi
                #preprocessing for system embtoolkit
                if [[ "$system" == "embtoolkit" ]]; then
                    find "$srctree" -type f -exec sed -i '/option env/d' {} \;
                    config_files=$(find "$srctree" -type f -name "Kconfig") 
                        for file in $config_files; do
                            sed -i -r -e 's|^source\s+"([^"]+)"|source "/home/input/embtoolkit/\1"|' \
                                -e 's|^source\s+([^"/][^"]*)|source "/home/input/embtoolkit/\1"|' "$file"
                        done
                    config_files=$(find "$srctree" -type f -name "*.kconfig") 
                        for file in $config_files; do
                            sed -i -r -e 's|^source\s+"([^"]+)"|source "/home/input/embtoolkit/\1"|' \
                            -e 's|^source\s+([^"/][^"]*)|source "/home/input/embtoolkit/\1"|' "$file"
                        done
                fi
                #preprocessing for system freetz-ng
                if [[ "$system" == "freetz-ng" ]]; then
                    config_files=$(find "$srctree" -type f -name "*.in") 
                    for file in $config_files; do
                        sed -i -r '/^\s*source\s+"make\/Config\.in\.generated"/d' "$file"
                        sed -i -r -e 's|^\s*source\s+"([^"]+)"|source "/home/input/freetz-ng/\1"|' \
                            -e 's|^\s*source\s+([^"/][^"]*)|source "/home/input/freetz-ng/\1"|' "$file"
                    done
                    config_files=$(find "$srctree" -type f -name "Config.in.busybox") 
                    for file in $config_files; do
                        sed -i -r '/^\s*source\s+"make\/Config\.in\.generated"/d' "$file"
                        sed -i -r -e 's|^\s*source\s+"([^"]+)"|source "/home/input/freetz-ng/\1"|' \
                            -e 's|^\s*source\s+([^"/][^"]*)|source "/home/input/freetz-ng/\1"|' "$file"
                    done
                fi
                #preprocessing for system toybox
                if [[ "$system" == "toybox" ]]; then
                    config_files=$(find "$srctree" -type f -name "*.in") 
                    for file in $config_files; do
                        sed -i -r -e 's|^\s*source\s+"([^"]+)"|source "/home/input/toybox/\1"|' \
                            -e 's|^\s*source\s+([^"/][^"]*)|source "/home/input/toybox/\1"|' "$file"
                    done
                fi
                make -f "$linux_source/Makefile" mrproper
                make -C "$linux_source" scripts/kconfig/cfoutconfig
                measure "$timeout"  make -C "$linux_source" cfoutconfig Kconfig=$KBUILD_KCONFIG | tee "$output_log"
                time=$((time+$(grep -oP "^measure_time=\K.*" < "$output_log")))
                if [[ -f "$linux_source/scripts/kconfig/cfout_constraints.txt" && -f "$linux_source/scripts/kconfig/cfout_constraints.features" ]]; then
                    cp "$linux_source/scripts/kconfig/cfout_constraints.txt" "$kconfig_model"
                            cp "$linux_source/scripts/kconfig/cfout_constraints.features" "$features_file"
                fi
            fi
            unset-environment "$environment"
        else
            echo "LKC binding file $lkc_binding_file does not exist"
        fi
    else
        echo "kconfig file $kconfig_file does not exist"
    fi
    pop
    trap - EXIT
    lkc_binding_file=${lkc_binding_file#"$(output-directory)/"}
    if is-file-empty "$kconfig_model"; then
        log "" "$(echo-fail)"
        kconfig_model=NA
    else
        log "" "$(echo-done)"
        # todo ConfigFix: review this
        if [[ $extractor != "configfix" ]]; then
            local features
            features=$(wc -l < "$features_file")
            local variables
            variables=$(sed "s/)/)\n/g" < "$kconfig_model" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
            local literals
            literals=$(sed "s/)/)\n/g" < "$kconfig_model" | grep -c "def(")
        else
            local features
            features=$(wc -l < "$features_file")
            local variables
            variables=$(sed "s/)/)\n/g" < "$kconfig_model" | grep "definedEx(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
            local literals
            literals=$(sed "s/)/)\n/g" < "$kconfig_model" | grep -c "definedEx(")
        fi

        kconfig_model=${kconfig_model#"$(output-directory)/"}
    fi
    echo "$system,$revision_clean,$architecture,$lkc_binding_file,$kconfig_file,${environment//,/|},$kconfig_model,$features,$variables,$literals,$time" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR and LKC_BINDING variables
register-kconfig-extractor(extractor, lkc_binding=, timeout=0) {
    EXTRACTOR=$extractor
    LKC_BINDING=$lkc_binding
    TIMEOUT=$timeout
    assert-value EXTRACTOR TIMEOUT
    # todo ConfigFix: review this (maybe create a dummy binding)
    if [ -z "$LKC_BINDING" ]; then
        echo "No LKC_BINDING provided, running without LKC_BINDING."
    else
        echo "Using LKC_BINDING: $LKC_BINDING"
    fi

    add-lkc-binding(system, revision, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        kconfig-checkout "$system" "$revision"
        if [ -n "$LKC_BINDING" ]; then
            compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
        fi
        git-clean "$(input-directory)/$system"
    }

    add-kconfig-model(system, revision, kconfig_file, lkc_binding_file=, environment=) {
        kconfig-checkout "$system" "$revision"
        extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
            "$system" "$revision" "$kconfig_file" "$lkc_binding_file" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        kconfig-checkout "$system" "$revision"
        if [ -n "$LKC_BINDING" ]; then
            compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
        fi
        extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
            "$system" "$revision" "$kconfig_file" "" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    echo system,revision,binding_file > "$(output-path lkc-bindings.csv)"
    echo system,revision,architecture,binding_file,kconfig_file,environment,model_file,model_features,model_variables,model_literals,model_time > "$(output-csv)"
}

# compiles LKC bindings and extracts kconfig models using kclause
extract-kconfig-models-with-kclause(timeout=0) {
    register-kconfig-extractor kclause kextractor "$timeout"
    experiment-systems
}

# compiles LKC bindings and extracts kconfig models using kconfigreader
extract-kconfig-models-with-kconfigreader(timeout=0) {
    register-kconfig-extractor kconfigreader dumpconf "$timeout"
    experiment-systems
}

extract-kconfig-models-with-configfix(timeout=0) {
    register-kconfig-extractor configfix "" "$timeout"
    experiment-systems
}
#!/bin/bash
# extracts kconfig models

# checks out a system and prepares it for further processing
kconfig-checkout(system, revision, kconfig_binding_files_spec=) {
    local revision_clean err
    revision_clean=$(clean-revision "$revision")
    push "$(input-directory)/$system"
    git-checkout "$revision_clean"
    # run system-specific code that may impair accuracy, but is necessary to extract a kconfig model
    compile-hook kconfig-post-checkout-hook
    kconfig-post-checkout-hook "$system" "$revision"
    if [[ -n $kconfig_binding_files_spec ]]; then
        local kconfig_binding_files
        kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
        local kconfig_binding_directory
        kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
        # make sure all dependencies for the kconfig binding are compiled
        if make "$kconfig_binding_files" >/dev/null 2>&1; then
            # some systems are weird and actually compile a *.o file, this is not what we want
            if [[ -f "$kconfig_binding_directory/"'*.o' ]]; then
                rm-safe "$kconfig_binding_directory/"'*.o'
                err=y
            fi
        else
            err=y
        fi
        if [[ -n $err ]]; then
            # make config sometimes asks for integers (not easily simulated with "yes"), which is why we add a timeout
            (yes | make allyesconfig >/dev/null 2>&1) \
            || (yes | make xconfig >/dev/null 2>&1) \
            || (yes "" | timeout 20s make config >/dev/null 2>&1) \
            || true
        fi
        if ls "$kconfig_binding_directory"/*.o > /dev/null 2>&1; then
            strip -N main "$kconfig_binding_directory"/*.o || true
        fi
    fi
    pop
}

# returns all files needed to compile a kconfig binding
kconfig-binding-files(kconfig_binding_files_spec) {
    echo "$kconfig_binding_files_spec" | tr , ' '
}

# returns the directory containing the kconfig binding files
kconfig-binding-directory(kconfig_binding_files_spec) {
    dirname "$(kconfig-binding-files "$kconfig_binding_files_spec")" | head -n1
}

# compiles a C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against the Kconfig parser, respectively
compile-kconfig-binding(kconfig_binding_name, system, revision, kconfig_binding_files_spec, environment=) {
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep)
    revision=$(clean-revision "$revision")
    local kconfig_binding_files
    kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
    local kconfig_binding_directory
    kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
    local kconfig_binding_output_file
    kconfig_binding_output_file="$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" "$system" "$revision.$kconfig_binding_name")"
    log "$kconfig_binding_name: $system@$revision"
    if [[ -f $kconfig_binding_output_file ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress compile)"
    push "$(input-directory)/$system"

    # determine which Kconfig constructs this system uses
    local gcc_arguments=""
    local construct
    for construct in "${kconfig_constructs[@]}"; do
        if grep -qrnw "$kconfig_binding_directory" -e "$construct" 2>/dev/null; then
            gcc_arguments="$gcc_arguments -DENUM_$construct"
        fi
    done

    # run system-specific code for influencing the binding compilation
    compile-hook kconfig-pre-binding-hook
    gcc_arguments="$gcc_arguments $(kconfig-pre-binding-hook "$system" "$revision" "$kconfig_binding_directory")"

    # shellcheck disable=SC2086
    if ls $kconfig_binding_files > /dev/null 2>&1; then
        local cmd="gcc ../../$kconfig_binding_name.c $kconfig_binding_files -I $kconfig_binding_directory -w -Werror=switch$gcc_arguments -o $kconfig_binding_output_file"
        (echo "$cmd" && eval "$cmd") || true
        chmod +x "$kconfig_binding_output_file" || true
    fi
    pop
    if [[ -f $kconfig_binding_output_file ]]; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        kconfig_binding_output_file=NA
    fi
    echo "$system,$revision,$kconfig_binding_output_file" >> "$(output-path kconfig-bindings.csv)"
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model(extractor, kconfig_binding=, system, revision, kconfig_file, kconfig_binding_file=, environment=, timeout=0) {
    local revision_clean
    revision_clean=$(clean-revision "$revision")
    local architecture
    architecture=$(get-architecture "$revision")
    if [[ -z "$kconfig_binding" ]]; then
        kconfig_binding_file=""
    else
        kconfig_binding_file=${kconfig_binding_file:-$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" "$system" "$revision_clean")}
        kconfig_binding_file+=.$kconfig_binding
    fi
    log "$extractor: $system@$revision"
    local file_extension="model"
    if [[ $extractor == configfixextractor ]]; then
        file_extension="model"
    fi
    if [[ -f $(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.model") ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress extract)"
    trap 'ec=$?; (( ec != 0 )) && rm-safe '"$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision")"'*' EXIT
    push "$(input-directory)/$system"
    local kconfig_model
    kconfig_model=$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.model")
    local features_file
    features_file=$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.features")
    local output_log
    output_log=$(mktemp)
    if [[ -f $kconfig_file ]]; then
        # todo ConfigFix: maybe create a dummy binding file for ConfigFix, so to avoid this parameter getting optional? (could just revert part of the change from the merge commit)
        if [[ -z "$kconfig_binding_file" || -f $kconfig_binding_file ]]; then
            set-environment "$environment"
            if [[ $extractor == kconfigreader ]]; then
                evaluate "$timeout" /home/kconfigreader/run.sh $(memory-limit 1) de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf "$kconfig_binding_file" "$kconfig_file" "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision")" | tee "$output_log"
                local time
                time=$(grep -oP "^evaluate_time=\K.*" < "$output_log")
            elif [[ $extractor == kclause ]]; then
                evaluate "$timeout" /home/kextractor.sh \
                    "$kconfig_binding_file" \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")" \
                    "$features_file" "$kconfig_file" \
                    | tee "$output_log"
                time=$(grep -oP "^evaluate_time=\K.*" < "$output_log")
                compile-hook kclause-post-binding-hook
                kclause-post-binding-hook "$system" "$revision"
                evaluate "$timeout" /home/kclause.sh \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")" \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kclause")" \
                    "$kconfig_model" \
                    | tee "$output_log"
                time=$((time+$(grep -oP "^evaluate_time=\K.*" < "$output_log")))
            elif [[ $extractor == configfixextractor ]]; then
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
                evaluate "$timeout"  make -C "$linux_source" cfoutconfig Kconfig=$KBUILD_KCONFIG | tee "$output_log"
                time=$((time+$(grep -oP "^evaluate_time=\K.*" < "$output_log")))
                if [[ -f "$linux_source/scripts/kconfig/cfout_constraints.txt" && -f "$linux_source/scripts/kconfig/cfout_constraints.features" ]]; then
                    cp "$linux_source/scripts/kconfig/cfout_constraints.txt" "$kconfig_model"
                            cp "$linux_source/scripts/kconfig/cfout_constraints.features" "$features_file"
                fi
            fi
            unset-environment "$environment"
        else
            echo "kconfig binding file $kconfig_binding_file does not exist"
        fi
    else
        echo "kconfig file $kconfig_file does not exist"
    fi
    pop
    trap - EXIT
    kconfig_binding_file=${kconfig_binding_file#"$(output-directory)/"}
    if is-file-empty "$kconfig_model"; then
        log "" "$(echo-fail)"
        kconfig_model=NA
    else
        log "" "$(echo-done)"
        # todo ConfigFix: review this
        if [[ $extractor != "configfixextractor" ]]; then
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
    echo "$system,$revision_clean,$architecture,$kconfig_binding_file,$kconfig_file,${environment//,/|},$kconfig_model,$features,$variables,$literals,$time" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR and KCONFIG_BINDING variables
register-kconfig-extractor(extractor, kconfig_binding=, timeout=0) {
    EXTRACTOR=$extractor
    KCONFIG_BINDING=$kconfig_binding
    TIMEOUT=$timeout
    assert-value EXTRACTOR TIMEOUT
    # todo ConfigFix: review this (maybe create a dummy binding)
    if [ -z "$KCONFIG_BINDING" ]; then
        echo "No KCONFIG_BINDING provided, running without KCONFIG_BINDING."
    else
        echo "Using KCONFIG_BINDING: $KCONFIG_BINDING"
    fi

    add-kconfig-binding(system, revision, kconfig_binding_files, environment=) {
        kconfig-checkout "$system" "$revision" "$kconfig_binding_files"
        if [ -n "$KCONFIG_BINDING" ]; then
            compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files" "$environment"
        fi
        git-clean "$(input-directory)/$system"
    }

    add-kconfig-model(system, revision, kconfig_file, kconfig_binding_file=, environment=) {
        kconfig-checkout "$system" "$revision"
        extract-kconfig-model "$EXTRACTOR" "$KCONFIG_BINDING" \
            "$system" "$revision" "$kconfig_file" "$kconfig_binding_file" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, kconfig_binding_files, environment=) {
        kconfig-checkout "$system" "$revision" "$kconfig_binding_files"
        if [ -n "$KCONFIG_BINDING" ]; then
            compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files" "$environment"
        fi
        extract-kconfig-model "$EXTRACTOR" "$KCONFIG_BINDING" \
            "$system" "$revision" "$kconfig_file" "" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    echo system,revision,binding-file > "$(output-path kconfig-bindings.csv)"
    echo system,revision,architecture,binding-file,kconfig-file,environment,model-file,model-features,model-variables,model-literals,model-time > "$(output-csv)"
}

# compiles kconfig bindings and extracts kconfig models using kclause
extract-kconfig-models-with-kclause(timeout=0) {
    register-kconfig-extractor kclause kextractor "$timeout"
    experiment-systems
}

# compiles kconfig bindings and extracts kconfig models using kconfigreader
extract-kconfig-models-with-kconfigreader(timeout=0) {
    register-kconfig-extractor kconfigreader dumpconf "$timeout"
    experiment-systems
}

extract-kconfig-models-with-configfixextractor(timeout=0) {
    register-kconfig-extractor configfixextractor "" "$timeout"
    experiment-systems
}
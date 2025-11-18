#!/bin/bash
# extracts kconfig models by adapting (variations of) LKC, the Linux kernel configurator

LKC_BINDINGS_DIRECTORY=lkc-bindings # output directory for storing LKC bindings
LKC_BINDINGS_OUTPUT_CSV=lkc-bindings.csv # output CSV file for storing LKC binding information
UVL_INPUT_KEY=uvl # the name of the input key to access flat UVL feature model files
UNCONSTRAINED_FEATURES_INPUT_KEY=unconstrained_features # the name of the input key to access unconstrained feature files

# checks out a system and prepares it for further processing
kconfig-checkout(system, revision) {
    log "" "$(echo-progress checkout)"
    local revision_without_context err
    revision_without_context=$(revision-without-context "$revision")
    push "$(input-directory)/$system"
    git-checkout "$revision_without_context"
    # run system-specific code that may impair accuracy, but is necessary to extract a kconfig model
    compile-hook kconfig-post-checkout-hook
    kconfig-post-checkout-hook "$system" "$revision"
    pop
    log "" "$(echo-done)"
}

# checks whether an LKC binding has already been compiled for the given system and revision
lkc-binding-done(system, revision) {
    local file revision_without_context
    file=$(output-path "$LKC_BINDINGS_OUTPUT_CSV")
    revision_without_context=$(revision-without-context "$revision")
    [[ -f $file ]] && grep -qP "^\Q$system,$revision_without_context,\E" "$file"
}

# checks whether a feature model has already been extracted for the given system and revision
kconfig-model-done(system, revision) {
    local file revision_without_context context
    file=$(output-csv)
    revision_without_context=$(revision-without-context "$revision")
    context=$(get-context "$revision")
    [[ -f $file ]] && grep -qP "^\Q$system,$revision_without_context,$context,\E" "$file"
}

# compiles a C program that extracts Kconfig constraints from Kconfig files
# for kconfigreader and kclause, this compiles dumpconf and kextractor against LKC's Kconfig parser, respectively
# lkc_directory must contain an implementation of LKC with a conf.c file, which we replace with the custom implementation given by the binding name
compile-lkc-binding(lkc_binding, system, revision, lkc_directory, lkc_target=config, lkc_output_directory=, environment=) {
    revision=$(revision-without-context "$revision")
    local lkc_binding_output_file
    lkc_binding_output_file="$(output-path "$LKC_BINDINGS_DIRECTORY" "$system" "$revision.$lkc_binding")"

    # compile the binding
    log "" "$(echo-progress compile)"
    push "$(input-directory)/$system"

    # explicitly expand possible wildcards in lkc_directory, which is necessary for systems that have a dynamic LKC path
    # shellcheck disable=SC2116 disable=SC2086
    lkc_directory=$(echo $lkc_directory)
    lkc_output_directory=${lkc_output_directory:-$lkc_directory}

    # override the default configurator with our own implementation, which just dumps all the configuration options and their dependencies for the extractor
    mkdir -p "$lkc_directory"
    cp "/home/$lkc_binding.c" "$lkc_directory/conf.c"

    # constructs to check for in the given implementation of LKC
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep sym_is_optional sym_get_choice_prop)

    # determine which Kconfig constructs this LKC implementation uses and enable them in our custom conf.c
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

    # record the compiled binding and mark it as done
    echo "$system,$revision,$lkc_binding_output_file" >> "$(output-path "$LKC_BINDINGS_OUTPUT_CSV")"
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model(extractor, lkc_binding=, system, revision, kconfig_file, lkc_binding_file=, environment=, timeout=0) {
    local revision_without_context context
    revision_without_context=$(revision-without-context "$revision")
    context=$(get-context "$revision")
    if [[ -z "$lkc_binding" ]]; then
        lkc_binding_file=""
    else
        lkc_binding_file=${lkc_binding_file:-$(output-path "$LKC_BINDINGS_DIRECTORY" "$system" "$revision_without_context")}
        lkc_binding_file+=.$lkc_binding
    fi
    local file_extension="model"
    if [[ $extractor == configfix ]]; then
        file_extension="model"
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
                export KBUILD_KCONFIG
                KBUILD_KCONFIG=$(realpath "$kconfig_file")
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
    rm-safe "$output_log"
    pop
    trap - EXIT
    lkc_binding_file=${lkc_binding_file#"$(output-directory)/"}
    if is-file-empty "$kconfig_model" || is-file-empty "$features_file"; then
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
    echo "$system,$revision_without_context,$context,$lkc_binding_file,$kconfig_file,${environment//,/|},$kconfig_model,$features,$variables,$literals,$time" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR, LKC_BINDING, TIMEOUT variables
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
        log "$system@$revision"
        if lkc-binding-done "$system" "$revision"; then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        # todo ConfigFix: review this (maybe create a dummy binding)
        if [ -n "$LKC_BINDING" ]; then
            compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
        fi
        git-clean "$(input-directory)/$system"
    }

    add-kconfig-model(system, revision, kconfig_file, lkc_binding_file=, environment=) {
        log "$system@$revision"
        if kconfig-model-done "$system" "$revision"; then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
            "$system" "$revision" "$kconfig_file" "$lkc_binding_file" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        log "$system@$revision"
        if lkc-binding-done "$system" "$revision" && kconfig-model-done "$system" "$revision"; then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        if [ -n "$LKC_BINDING" ]; then # todo ConfigFix: review this
            if ! lkc-binding-done "$system" "$revision"; then
                compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
            fi
        fi
        if ! kconfig-model-done "$system" "$revision"; then
            extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
                "$system" "$revision" "$kconfig_file" "" "$environment" "$TIMEOUT"
        fi
        git-clean "$(input-directory)/$system"
    }

    if [[ ! -f $(output-path "$LKC_BINDINGS_OUTPUT_CSV") ]]; then
        echo system,revision,binding_file > "$(output-path "$LKC_BINDINGS_OUTPUT_CSV")"
    fi
    if [[ ! -f $(output-csv) ]]; then
        echo system,revision,context,binding_file,kconfig_file,environment,model_file,model_features,model_variables,model_literals,model_time > "$(output-csv)"
    fi
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

# extracts a non-flat UVL feature hierarchy from KConfig files by leveraging their menu structure
# relies on KConfiglib for parsing the KConfig files, which may not succeed for all systems and revisions
# so this is an optional step that can be used to enrich a flat UVL feature model with a hierarchy
extract-kconfig-hierarchy(system, revision, kconfig_file, lkc_directory, lkc_target=config, environment=, timeout=0) {
    local revision_without_context context uvl_file unconstrained_features_file output_file report_file
    revision_without_context=$(revision-without-context "$revision")
    context=$(get-context "$revision")
    push "$(input-directory)/$system"

    # set up the environment for successful parsing with KConfiglib
    set-environment "$environment"

    # some systems require generating intermediate files before KConfiglib can parse the KConfig files properly
    # usually this can be done by running `make <target>`, typically `make config`
    if [[ -n "$lkc_directory" ]]; then
        echo "int main(void){return 0;}" > "$lkc_directory/conf.c"
        yes "" | make "$lkc_target" >/dev/null 2>&1 || true
    fi

    # run system-specific code for influencing the hierarchy extraction, if needed
    compile-hook kconfig-pre-hierarchy-hook
    kconfig-pre-hierarchy-hook "$system" "$revision"

    while read -r relative_uvl_file; do
        log "$relative_uvl_file"
        log "" "$(echo-progress extract)"
        unconstrained_features_file=$(input-directory "$UNCONSTRAINED_FEATURES_INPUT_KEY")/${relative_uvl_file%.uvl}.unconstrained.features
        output_file="$(output-path "$relative_uvl_file")"
        report_file="$(output-path "${relative_uvl_file%.uvl}.report")"
        uvl_file=$(input-directory "$UVL_INPUT_KEY")/$relative_uvl_file
        if [[ -f "$uvl_file" ]] && [[ -f "$unconstrained_features_file" ]]; then
            # parse with KConfiglib and extract the hierarchy
            python3 /home/Kconfiglib/extract_hierarchy.py "$kconfig_file" "$uvl_file" "$unconstrained_features_file" "$output_file" "$report_file"
            log "" "$(echo-done)"
        else
            log "" "$(echo-fail)"
        fi

        # record the extracted hierarchy and mark it as done
        echo "$system,$revision_without_context,$context,${environment//,/|},$relative_uvl_file" >> "$(output-csv)"
    done < <(table-field "$(input-csv "$UVL_INPUT_KEY")" uvl_file | grep "$(compose-path "$system" "$revision.uvl")")

    unset-environment "$environment"
    pop
}

# defines API functions for extracting kconfig hierarchies
# sets the global TIMEOUT variable
extract-kconfig-hierarchies-with-kconfiglib(timeout=0) {
    TIMEOUT=$timeout

    add-kconfig-model(system, revision, kconfig_file, lkc_binding_file=, environment=) {
        log "$system@$revision"
        kconfig-checkout "$system" "$revision"
        extract-kconfig-hierarchy "$system" "$revision" "$kconfig_file" "" "" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        log "$system@$revision"
        kconfig-checkout "$system" "$revision"
        extract-kconfig-hierarchy "$system" "$revision" "$kconfig_file" "$lkc_directory" "$lkc_target" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    if [[ ! -f $(output-csv) ]]; then
        echo system,revision,context,environment,uvl_file > "$(output-csv)"
    fi

    experiment-systems
}

# expresses the intent to mount everything needed for hierarchy extraction
# can be passed as --input to solve(...)
mount-for-hierarchy-extraction(input=, uvl_input=transform-model-to-uvl-with-featureide, unconstrained_features_input=compute-unconstrained-features) {
    input=${input:-$ROOT_STAGE}
    echo "$MAIN_INPUT_KEY=$input,$UVL_INPUT_KEY=$uvl_input,$UNCONSTRAINED_FEATURES_INPUT_KEY=$unconstrained_features_input"
}
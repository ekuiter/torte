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
# this ensures that the parser understands all Kconfig constructs used by the given system and revision and translates them correctly in terms of semantics
# for configfix, we skip this step, because it is tightly integrated with LKC and very hard to adapt to other systems and revisions
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

# runs KConfigReader to extract a feature-model formula from Kconfig files
# sets the global MEASURED_TIME variable
extract-kconfig-model-with-kconfigreader(system, revision, kconfig_file, lkc_binding_file, output_log, timeout=0) {
    measure "$timeout" /home/kconfigreader/run.sh \
        "$(memory-limit 1)" \
        de.fosd.typechef.kconfig.KConfigReader \
        --fast \
        --dumpconf "$lkc_binding_file" \
        "$kconfig_file" \
        "$(output-path "$system" "$revision")" \
        | tee "$output_log"
    MEASURED_TIME=$(grep -oP "^measure_time=\K.*" < "$output_log")
}

# runs KClause to extract a feature-model formula from Kconfig files
# sets the global MEASURED_TIME variable
extract-kconfig-model-with-kclause(system, revision, kconfig_file, lkc_binding_file, kconfig_model, features_file, output_log, options=, timeout=0) {
    measure "$timeout" /home/kextractor.sh \
        "$lkc_binding_file" \
        "$(output-path "$system" "$revision.kextractor")" \
        "$features_file" "$kconfig_file" \
        | tee "$output_log"
    MEASURED_TIME=$(grep -oP "^measure_time=\K.*" < "$output_log")
    compile-hook kclause-post-binding-hook
    kclause-post-binding-hook "$system" "$revision"
    # as documented in the README file, we consider --disable-tristate-support to be the sensible default
    # thus, we explicitly make tristate support opt-in here
    if [[ -z "$options" ]]; then
        options="--disable-tristate-support"
    elif [[ $options == "--enable-tristate-support" ]]; then
        options=
    fi
    # shellcheck disable=SC2086
    measure "$timeout" /home/kclause.sh \
        "$(output-path "$system" "$revision.kextractor")" \
        "$(output-path "$system" "$revision.kclause")" \
        "$kconfig_model" \
        $options \
        | tee "$output_log"
    MEASURED_TIME=$((MEASURED_TIME+$(grep -oP "^measure_time=\K.*" < "$output_log")))
}

# runs ConfigFix to extract a feature-model formula from Kconfig files
# sets the global MEASURED_TIME variable
extract-kconfig-model-with-configfix(system, revision, kconfig_file, kconfig_model, features_file, output_log, lkc_directory, lkc_target=config, lkc_output_directory=, options=, timeout=0) {
    local configfix_directory=/home/torte-ConfigFix override_lkc_target

    # the following three lines are only needed to address a bug in ConfigFix
    # for systems that don't define a list of defconfigs, we need an empty dummy file (instead of an empty list) to avoid a segmentation fault inside of ConfigFix
    # for systems like Linux, these lines have no effect because the list will be overwritten in the makefile anyway
    export KCONFIG_DEFCONFIG_LIST
    KCONFIG_DEFCONFIG_LIST=/home/empty-kconfig-defconfig-list.txt
    touch "$KCONFIG_DEFCONFIG_LIST"

    # allow for system-specific adaptations before running ConfigFix
    # typically this will transform KConfig files to adhere to the rigid syntactical expectations of ConfigFix, as we have no flexible binding compilation here
    compile-hook configfix-pre-extraction-hook
    override_lkc_target=$(configfix-pre-extraction-hook "$system" "$revision" | grep -oP '^override-lkc-target=\K.*' || true)
    if [[ -n $override_lkc_target ]]; then
        lkc_target=$override_lkc_target
    fi

    # for extraction, we use a different approach than for KClause and KConfigReader, because ConfigFix is tightly integrated with LKC
    # there is no separate binding stage, instead we run ConfigFix directly on the Kconfig file
    # the question is how to call ConfigFix such that the correct environment variables are passed
    # we offer two options for this, which can be controlled via lkc_output_directory and lkc_target
    # the first option works better if no LKC environment is needed (e.g., for standalone KConfig files)
    # the second option works better if LKC plays a larger role (e.g., for BusyBox or Linux)
    if [[ $lkc_output_directory == $(none) ]] || [[ $lkc_target == $(none) ]]; then
        # either we run the compiled ConfigFix binary directly on the Kconfig file (simpler, but only passes explicitly specified --environment)
        measure "$timeout" "$configfix_directory/scripts/kconfig/cfoutconfig" \
            "$kconfig_file" \
            | tee "$output_log"
    else
        # or we hijack LKC's makefile to run ConfigFix via "make config" (more complex, but also includes environment variables set by the makefiles)
        # this uses similar mechanisms as compile-lkc-binding above
        # this has the disadvantage that we cannot explicitly specify the Kconfig file location, but must rely on LKC's makefiles to find it
        # (sometimes there is a KBUILD_KCONFIG variable that we override here, but not all systems and revisions will respect this)
        # shellcheck disable=SC2116 disable=SC2086
        # to do this, we first prepare several paths ...
        lkc_directory=$(echo $lkc_directory)
        lkc_output_directory=${lkc_output_directory:-$lkc_directory}
        mkdir -p "$lkc_directory"
        # ... then we compile a dummy "make config" implementation ...
        echo "int main(){return 0;}" > "$lkc_directory/conf.c"
        yes "" | make "$lkc_target" KBUILD_KCONFIG="$kconfig_file" >/dev/null 2>&1 || true
        # ... which we can then replace with the ConfigFix binary ...
        cp "$configfix_directory/scripts/kconfig/cfoutconfig" "$lkc_output_directory/conf"
        # ... and finally we run "make <target>" to execute ConfigFix with all the right environment variables
        measure "$timeout" make "$lkc_target" \
            | tee "$output_log"
    fi

    MEASURED_TIME=$(grep -oP "^measure_time=\K.*" < "$output_log")
    if [[ -f cfout_constraints.txt ]] && [[ -f cfout_constraints.dimacs ]]; then
        # translate ConfigFix's output to the standard .model format produced by KConfigReader
        /home/configfix2model.sh cfout_constraints.txt
        cp cfout_constraints.txt "$kconfig_model"
        # ConfigFix is also able to produce a CNF with its internal Tseitin transformation
        # we do not use this CNF for further processing, but we store it nonetheless if requested
        # this is opt-in to save disk space
        # this transformation is tightly integrated with the extraction (via internal data structures)
        # thus, we do not decouple it as a transformation stage (as done for KConfigReader)
        if [[ $options == "--with-dimacs" ]]; then
            cp cfout_constraints.dimacs "$(output-path "$system" "$revision.dimacs")"
        fi
        # ConfigFix does not export an explicit feature list, unfortunately
        echo "ConfigFix does not offer a built-in feature extraction." > "$features_file"
    fi
}

# wraps source statements in the selected KConfig files the working directory in double quotes
# this is necessary for extraction with ConfigFix, which cannot parse unquoted paths
wrap-source-statements-in-double-quotes(file_query...) {
    if [[ ${#file_query[@]} -eq 0 ]]; then
        file_query=(-name Config.in)
    fi
    find . "${file_query[@]}" -exec sed -i -r 's|^[[:space:]]*source[[:space:]]+([^"].*)$|source "\1"|' {} \;
}

# until Linux 4.18, option env is used to import environment variables into the KConfig namespace
# this is not supported by ConfigFix (which is roughly based on LKC in Linux 6.14) and must be removed
# see https://stackoverflow.com/q/10099478
# this has no impact because we are usually not interested in default values derived from environment variables
remove-environment-variable-imports(file_query...) {
    if [[ ${#file_query[@]} -eq 0 ]]; then
        file_query=(-name Config.in)
    fi
    find . "${file_query[@]}" -exec sed -i '/option env/d' {} \;
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model(extractor, lkc_binding, system, revision, kconfig_file, lkc_binding_file=, lkc_directory, lkc_target=config, lkc_output_directory=, environment=, options=, timeout=0) {
    local revision_without_context context time
    revision_without_context=$(revision-without-context "$revision")
    context=$(get-context "$revision")
    if [[ $lkc_binding == $(none) ]] || [[ $lkc_binding_file == $(none) ]]; then
        lkc_binding_file=NA
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
    set-environment "$environment"
    if [[ $extractor != configfix ]]; then
        # at this point, the KConfig file should already have been generated by the makefiles during binding compilation
        if [[ -f $kconfig_file ]]; then
            if [[ -f $lkc_binding_file ]]; then
                if [[ $extractor == kconfigreader ]]; then
                    extract-kconfig-model-with-kconfigreader \
                        "$system" "$revision" "$kconfig_file" "$lkc_binding_file" "$output_log" "$timeout"
                elif [[ $extractor == kclause ]]; then
                    extract-kconfig-model-with-kclause \
                        "$system" "$revision" "$kconfig_file" "$lkc_binding_file" "$kconfig_model" "$features_file" "$output_log" "$options" "$timeout"
                fi
            else
                echo "LKC binding file $lkc_binding_file does not exist"
            fi
        else
            echo "kconfig file $kconfig_file does not exist"
        fi
    else
        # for ConfigFix, the root KConfig file may yet have to be generated, which is why we skip its validation here
        extract-kconfig-model-with-configfix \
            "$system" "$revision" "$kconfig_file" "$kconfig_model" "$features_file" "$output_log" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$options" "$timeout"
    fi
    unset-environment "$environment"
    rm-safe "$output_log"
    pop
    trap - EXIT
    lkc_binding_file=${lkc_binding_file#"$(output-directory)/"}
    if is-file-empty "$kconfig_model" || is-file-empty "$features_file"; then
        log "" "$(echo-fail)"
        kconfig_model=NA
    else
        log "" "$(echo-done)"
        local features=NA variables=NA literals=NA
        if [[ $extractor != configfix ]]; then
            features=$(wc -l < "$features_file")
        fi
        variables=$(sed "s/)/)\n/g" < "$kconfig_model" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
        literals=$(sed "s/)/)\n/g" < "$kconfig_model" | grep -c "def(")
        kconfig_model=${kconfig_model#"$(output-directory)/"}
    fi
    echo "$system,$revision_without_context,$context,$lkc_binding_file,$kconfig_file,${environment//,/|},$options,$kconfig_model,$features,$variables,$literals,$MEASURED_TIME" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR, LKC_BINDING, TIMEOUT variables
register-kconfig-extractor(extractor, lkc_binding, options=, timeout=0) {
    EXTRACTOR=$extractor
    LKC_BINDING=$lkc_binding
    OPTIONS=$options
    TIMEOUT=$timeout
    assert-value EXTRACTOR TIMEOUT

    add-lkc-binding(system, revision, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        log "$system@$revision"
        if lkc-binding-done "$system" "$revision" || should-skip compile-lkc-binding "" "$system" "$revision"; then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        if [[ $LKC_BINDING != $(none) ]]; then
            compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
        fi
        git-clean "$(input-directory)/$system"
    }

    add-kconfig-model(system, revision, kconfig_file, lkc_binding_file, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        log "$system@$revision"
        if kconfig-model-done "$system" "$revision" || should-skip extract-kconfig-model "" "$system" "$revision"; then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
            "$system" "$revision" "$kconfig_file" "$lkc_binding_file" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment" "$OPTIONS" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, lkc_directory, lkc_target=, lkc_output_directory=, environment=) {
        log "$system@$revision"
        if (lkc-binding-done "$system" "$revision" && kconfig-model-done "$system" "$revision") \
            || (should-skip compile-lkc-binding "" "$system" "$revision" && should-skip extract-kconfig-model "" "$system" "$revision"); then
            log "" "$(echo-skip)"
            return
        fi
        kconfig-checkout "$system" "$revision"
        if [[ $LKC_BINDING != $(none) ]] && ! lkc-binding-done "$system" "$revision" && ! should-skip compile-lkc-binding "" "$system" "$revision"; then
            compile-lkc-binding "$LKC_BINDING" "$system" "$revision" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment"
        fi
        if ! kconfig-model-done "$system" "$revision" && ! should-skip extract-kconfig-model "" "$system" "$revision"; then
            extract-kconfig-model "$EXTRACTOR" "$LKC_BINDING" \
                "$system" "$revision" "$kconfig_file" "" "$lkc_directory" "$lkc_target" "$lkc_output_directory" "$environment" "$OPTIONS" "$TIMEOUT"
        fi
        git-clean "$(input-directory)/$system"
    }

    if [[ ! -f $(output-path "$LKC_BINDINGS_OUTPUT_CSV") ]]; then
        echo system,revision,binding_file > "$(output-path "$LKC_BINDINGS_OUTPUT_CSV")"
    fi
    if [[ ! -f $(output-csv) ]]; then
        echo system,revision,context,binding_file,kconfig_file,environment,options,model_file,model_features,model_variables,model_literals,model_time > "$(output-csv)"
    fi
}

# compiles LKC bindings and extracts kconfig models using kclause
extract-kconfig-models-with-kclause(options=, timeout=0) {
    register-kconfig-extractor kclause kextractor "$options" "$timeout"
    experiment-systems
}

# compiles LKC bindings and extracts kconfig models using kconfigreader
extract-kconfig-models-with-kconfigreader(options=, timeout=0) {
    register-kconfig-extractor kconfigreader dumpconf "$options" "$timeout"
    experiment-systems
}

# extracts kconfig models using configfix, which does not use a revision-tailored LKC binding
extract-kconfig-models-with-configfix(options=, timeout=0) {
    register-kconfig-extractor configfix "$(none)" "$options" "$timeout"
    experiment-systems
}

# extracts a non-flat UVL feature hierarchy from KConfig files by leveraging their menu structure
# relies on KConfiglib for parsing the KConfig files, which may not succeed for all systems and revisions
# so this is an optional step that can be used to enrich a flat UVL feature model with a hierarchy
extract-kconfig-hierarchy(system, revision, kconfig_file, lkc_directory=, lkc_target=config, environment=, timeout=0) {
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

    # parse with KConfiglib and extract the hierarchy for each UVL file belonging to this system and revision
    while read -r relative_uvl_file; do
        log "$relative_uvl_file"
        log "" "$(echo-progress extract)"
        unconstrained_features_file=$(input-directory "$UNCONSTRAINED_FEATURES_INPUT_KEY")/${relative_uvl_file%.uvl}.unconstrained.features
        output_file="$(output-path "$relative_uvl_file")"
        report_file="$(output-path "${relative_uvl_file%.uvl}.txt")"
        uvl_file=$(input-directory "$UVL_INPUT_KEY")/$relative_uvl_file
        if [[ -f "$uvl_file" ]] && [[ -f "$unconstrained_features_file" ]]; then
            measure "$timeout" python3 /home/Kconfiglib/extract_hierarchy.py "$kconfig_file" "$uvl_file" "$unconstrained_features_file" "$output_file" "$report_file"
            log "" "$(echo-done)"
        fi
        if [[ -f "$output_file" ]]; then
            log "" "$(echo-done)"
        else
            log "" "$(echo-fail)"
        fi

        # record the extracted hierarchy and mark it as done
        echo "$system,$revision_without_context,$context,${environment//,/|},$relative_uvl_file" >> "$(output-csv)"
    done < <(table-field "$(input-csv "$UVL_INPUT_KEY")" uvl_file | grep -F "$(compose-path "$system" "$revision.uvl")")

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
mount-for-hierarchy-extraction(input=, uvl_input=transform-to-uvl-with-featureide, unconstrained_features_input=compute-unconstrained-features) {
    input=${input:-$ROOT_STAGE}
    echo "$MAIN_INPUT_KEY=$input,$UVL_INPUT_KEY=$uvl_input,$UNCONSTRAINED_FEATURES_INPUT_KEY=$unconstrained_features_input"
}
#!/bin/bash

# checks out a subject and prepares it for further processing
kconfig-checkout(system, revision, kconfig_binding_files_spec=) {
    push "$(input-directory)/$system"
    git-checkout "$revision" "$PWD"
    kconfig-post-checkout-hook "$system" "$revision"
    if [[ -n $kconfig_binding_files_spec ]]; then
        local kconfig_binding_files
        kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
        local kconfig_binding_directory
        kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
        # make sure all dependencies for the kconfig binding are compiled
        # make config sometimes asks for integers (not easily simulated with "yes"), which is why we add a timeout
        make "$kconfig_binding_files" >/dev/null 2>&1 \
            || (yes | make allyesconfig >/dev/null 2>&1) \
            || (yes | make xconfig >/dev/null 2>&1) \
            || (yes "" | timeout 20s make config >/dev/null 2>&1) \
            || true
        strip -N main "$kconfig_binding_directory"/*.o || true
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
compile-kconfig-binding(kconfig_binding_name, system, revision, kconfig_binding_files_spec) {
    local kconfig_constructs=(S_UNKNOWN S_BOOLEAN S_TRISTATE S_INT S_HEX S_STRING S_OTHER P_UNKNOWN \
        P_PROMPT P_COMMENT P_MENU P_DEFAULT P_CHOICE P_SELECT P_RANGE P_ENV P_SYMBOL E_SYMBOL E_NOT \
        E_EQUAL E_UNEQUAL E_OR E_AND E_LIST E_RANGE E_CHOICE P_IMPLY E_NONE E_LTH E_LEQ E_GTH E_GEQ \
        dir_dep)
    local kconfig_binding_files
    kconfig_binding_files=$(kconfig-binding-files "$kconfig_binding_files_spec")
    local kconfig_binding_directory
    kconfig_binding_directory=$(kconfig-binding-directory "$kconfig_binding_files_spec")
    local kconfig_binding_output_file
    kconfig_binding_output_file=$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system/$revision.$kconfig_binding_name
    log "$kconfig_binding_name: $system@$revision"
    if [[ -f $kconfig_binding_output_file ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress compile)"
    mkdir -p "$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system"
    push "$(input-directory)/$system"

    # determine which Kconfig constructs this system uses
    local gcc_arguments=""
    local construct
    for construct in "${kconfig_constructs[@]}"; do
        if grep -qrnw "$kconfig_binding_directory" -e "$construct" 2>/dev/null; then
            gcc_arguments="$gcc_arguments -DENUM_$construct"
        fi
    done

    local cmd="gcc ../../$kconfig_binding_name.c $kconfig_binding_files -I $kconfig_binding_directory -w -Werror=switch$gcc_arguments -o $kconfig_binding_output_file"
    (echo "$cmd" && eval "$cmd") || true
    chmod +x "$kconfig_binding_output_file" || true
    pop
    if [[ -f $kconfig_binding_output_file ]]; then
        log "" "$(echo-done)"
    else
        log "" "$(echo-fail)"
        kconfig_binding_output_file=NA
    fi
    echo "$system,$revision,$kconfig_binding_output_file" >> "$(output-directory)/kconfig-bindings.csv"
}

# extracts a feature model in form of a logical formula from a kconfig-based software system
# it is suggested to run compile-c-binding beforehand, first to get an accurate kconfig parser, second because the make call generates files this function may need
extract-kconfig-model(extractor, kconfig_binding, system, revision, kconfig_file, kconfig_binding_file=, env=) {
    kconfig_binding_file=${kconfig_binding_file:-$(output-directory)/$KCONFIG_BINDINGS_OUTPUT_DIRECTORY/$system/$revision.$kconfig_binding}
    if [[ -n $env ]]; then
        env="$(echo '' -e "$env" | sed 's/,/ -e /g')"
    fi
    log "$extractor: $system@$revision"
    if [[ -f $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.model ]]; then
        log "" "$(echo-skip)"
        return
    fi
    log "" "$(echo-progress extract)"
    trap 'ec=$?; (( ec != 0 )) && rm-safe '"$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision"'*' EXIT
    mkdir -p "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system"
    push "$(input-directory)/$system"
    local kconfig_model
    local start
    local cmd
    local end
    kconfig_model="$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.model"
    if [[ $extractor == kconfigreader ]]; then
        # todo: migrate start,end, and cmd to use measure-time
        start=$(date +%s.%N)
        cmd="/home/kconfigreader/run.sh de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf $kconfig_binding_file $kconfig_file $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision"
        (echo "$cmd" && eval "$cmd") || true
        end=$(date +%s.%N)
    elif [[ $extractor == kclause ]]; then
        start=$(date +%s.%N)
        cmd="$kconfig_binding_file --extract -o $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.kclause $env $kconfig_file"
        (echo "$cmd" && eval "$cmd") || true
        cmd="$kconfig_binding_file --configs $env $kconfig_file > $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.features"
        (echo "$cmd" && eval "$cmd") || true
        kclause-post-binding-hook "$system" "$revision"
        cmd="kclause < $(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.kclause > $kconfig_model"
        (echo "$cmd" && eval "$cmd") || true
        end=$(date +%s.%N)
        local kconfig_model_tmp
        kconfig_model_tmp=$(mktemp)
        cmd="python3 /home/kclause2model.py $kconfig_model > $kconfig_model_tmp && mv $kconfig_model_tmp $kconfig_model"
        (echo "$cmd" && eval "$cmd") || true
    fi
    echo "#item time $(echo "($end - $start) * 1000000000 / 1" | bc)" >> "$kconfig_model"
    pop
    trap - EXIT
    kconfig_binding_file=${kconfig_binding_file#"$(output-directory)/"}
    if is-file-empty "$kconfig_model"; then
        log "" "$(echo-fail)"
        kconfig_model=NA
    else
        log "" "$(echo-done)"
        kconfig_model=${kconfig_model#"$(output-directory)/"}
    fi
    echo "$system,$revision,$kconfig_binding_file,$kconfig_file,$kconfig_model" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR and KCONFIG_BINDING variables
# shellcheck disable=SC2317
register-kconfig-extractor() {
    EXTRACTOR=$1
    KCONFIG_BINDING=$2
    require-value EXTRACTOR KCONFIG_BINDING

    # todo: separate binding and model stages?
    add-kconfig-binding(system, revision, kconfig_binding_files_spec) {
        kconfig-checkout "$system" "$revision" "$kconfig_binding_files_spec"
        compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files_spec"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig-model(system, revision, kconfig_file, kconfig_binding_file=, env=) {
        kconfig-checkout "$system" "$revision"
        extract-kconfig-model "$EXTRACTOR" "$KCONFIG_BINDING" \
            "$system" "$revision" "$kconfig_file" "$kconfig_binding_file" "$env"
        git-clean "$(input-directory)/$system"
    }

    add-kconfig(system, revision, kconfig_file, kconfig_binding_files_spec, env=) {
        kconfig-checkout "$system" "$revision" "$kconfig_binding_files_spec"
        compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files_spec"
        extract-kconfig-model "$EXTRACTOR" "$KCONFIG_BINDING" \
            "$system" "$revision" "$kconfig_file" "" "$env"
        git-clean "$(input-directory)/$system"
    }

    echo system,revision,binding-file > "$(output-directory)/kconfig-bindings.csv"
    echo system,revision,binding-file,kconfig-file,model-file > "$(output-csv)"
}

# compiles kconfig bindings and extracts kconfig models using kclause
extract-with-kclause() {
    register-kconfig-extractor kclause kextractor
    experiment-subjects
}

# compiles kconfig bindings and extracts kconfig models using kconfigreader
extract-with-kconfigreader() {
    register-kconfig-extractor kconfigreader dumpconf
    experiment-subjects
}
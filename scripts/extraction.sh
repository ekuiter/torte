#!/bin/bash

# checks out a subject and prepares it for further processing
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
# for kconfigreader and kmax, this compiles dumpconf and kextractor against the Kconfig parser, respectively
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
extract-kconfig-model(extractor, kconfig_binding, system, revision, kconfig_file, kconfig_binding_file=, environment=, timeout=0) {
    local revision_clean
    revision_clean=$(clean-revision "$revision")
    local architecture
    architecture=$(get-architecture "$revision")
    kconfig_binding_file=${kconfig_binding_file:-$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" "$system" "$revision_clean")}
    kconfig_binding_file+=.$kconfig_binding
    log "$extractor: $system@$revision"
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
        if [[ -f $kconfig_binding_file ]]; then
            set-environment "$environment"
            if [[ $extractor == kconfigreader ]]; then
                evaluate "$timeout" /home/kconfigreader/run.sh de.fosd.typechef.kconfig.KConfigReader --fast --dumpconf "$kconfig_binding_file" "$kconfig_file" "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision")" | tee "$output_log"
                local time
                time=$(grep -oP "^evaluate_time=\K.*" < "$output_log")
            elif [[ $extractor == kmax ]]; then
                evaluate "$timeout" /home/kextractor.sh \
                    "$kconfig_binding_file" \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")" \
                    "$features_file" "$kconfig_file" \
                    | tee "$output_log"
                time=$(grep -oP "^evaluate_time=\K.*" < "$output_log")
                compile-hook kmax-post-binding-hook
                kmax-post-binding-hook "$system" "$revision"
                evaluate "$timeout" /home/kclause.sh \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")" \
                    "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kclause")" \
                    "$kconfig_model" \
                    | tee "$output_log"
                time=$((time+$(grep -oP "^evaluate_time=\K.*" < "$output_log")))
	    elif [[ $extractor == configfixextractor ]]; then
		    echo "Running manual Kconfig extraction"

		
		    if [[ ! -d /home/linux/linux-6.10 ]]; then
			echo "Das Verzeichnis /home/linux/linux-6.10 existiert nicht. Bitte sicherstellen, dass das Verzeichnis korrekt ist."
			exit 1
		    fi


		    echo "Wechsle ins Verzeichnis /home/linux/linux-6.10"
		    pushd /home/linux/linux-6.10

		    # Schritt 1: Makefile für scripts/kconfig/cfoutconfig
		    echo "Führe 'make scripts/kconfig/cfoutconfig' aus"
		    make scripts/kconfig/cfoutconfig
		    if [[ $? -ne 0 ]]; then
			echo "Fehler: 'make scripts/kconfig/cfoutconfig' ist fehlgeschlagen"
			popd
			exit 1
		    fi

		    # Schritt 2: make cfoutconfig mit dem Kconfig-File
		    echo "Führe 'make cfoutconfig Kconfig=kconfig_file' aus"
		    make cfoutconfig Kconfig=kconfig_file
		    if [[ $? -ne 0 ]]; then
			echo "Fehler: 'make cfoutconfig Kconfig=Kconfig' ist fehlgeschlagen"
			popd
			exit 1
		    fi

		    # Schritt 3: make mit spezifischem Makefile und Kconfig-File
		    echo "Führe 'make -f /home/linux/linux-6.10/Makefile cfoutconfig Kconfig=kconfig_file' aus"
		    make -f /home/linux/linux-6.10/Makefile cfoutconfig Kconfig=kconfig_file
		    if [[ $? -ne 0 ]]; then
			echo "Fehler: 'make -f /home/linux/linux-6.10/Makefile cfoutconfig Kconfig=Kconfig' ist fehlgeschlagen"
			popd
			exit 1
		    fi

		    # Ergebnisse loggen
		    popd
		    kconfig_model=$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.model")
		    echo "Kconfig-Modell wurde unter $kconfig_model generiert"

		    # Zeitmessung der Extraktion
		    time=$(date +%s)
		    echo "Extraktion abgeschlossen in $time Sekunden"
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
        local features
        features=$(wc -l < "$features_file")
        local variables
        variables=$(sed "s/)/)\n/g" < "$kconfig_model" | grep "def(" | sed "s/.*def(\(.*\)).*/\1/g" | sort | uniq | wc -l)
        local literals
        literals=$(sed "s/)/)\n/g" < "$kconfig_model" | grep -c "def(")
        kconfig_model=${kconfig_model#"$(output-directory)/"}
    fi
    echo "$system,$revision_clean,$architecture,$kconfig_binding_file,$kconfig_file,${environment//,/|},$kconfig_model,$features,$variables,$literals,$time" >> "$(output-csv)"
}

# defines API functions for extracting kconfig models
# sets the global EXTRACTOR and KCONFIG_BINDING variables
register-kconfig-extractor(extractor, kconfig_binding, timeout=0) {
    EXTRACTOR=$extractor
    KCONFIG_BINDING=$kconfig_binding
    TIMEOUT=$timeout
    require-value EXTRACTOR KCONFIG_BINDING TIMEOUT

    add-kconfig-binding(system, revision, kconfig_binding_files, environment=) {
        kconfig-checkout "$system" "$revision" "$kconfig_binding_files"
        compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files" "$environment"
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
        compile-kconfig-binding "$KCONFIG_BINDING" "$system" "$revision" "$kconfig_binding_files" "$environment"
        extract-kconfig-model "$EXTRACTOR" "$KCONFIG_BINDING" \
            "$system" "$revision" "$kconfig_file" "" "$environment" "$TIMEOUT"
        git-clean "$(input-directory)/$system"
    }

    echo system,revision,binding-file > "$(output-path kconfig-bindings.csv)"
    echo system,revision,architecture,binding-file,kconfig-file,environment,model-file,model-features,model-variables,model-literals,model-time > "$(output-csv)"
}

# compiles kconfig bindings and extracts kconfig models using kmax
extract-kconfig-models-with-kmax(timeout=0) {
    register-kconfig-extractor kmax kextractor "$timeout"
    experiment-subjects
}

# compiles kconfig bindings and extracts kconfig models using kconfigreader
extract-kconfig-models-with-kconfigreader(timeout=0) {
    register-kconfig-extractor kconfigreader dumpconf "$timeout"
    experiment-subjects
}

extract-kconfig-models-with-configfixextractor(timeout=0) {
    register-kconfig-extractor configfixextractor  cfoutconfig "$timeout"
    experiment-subjects
}










#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Extraction and comparison of all feature models of several feature-model histories

PASSES=(main commits)

download-additional-models() {
    additional_model_urls=(
        finance/FinancialServices01/Nieke2018-2017-05-22.xml
        finance/FinancialServices01/Nieke2018-2017-09-28.xml
        finance/FinancialServices01/Nieke2018-2017-10-20.xml
        finance/FinancialServices01/Nieke2018-2017-11-20.xml
        finance/FinancialServices01/Nieke2018-2017-12-22.xml
        finance/FinancialServices01/Nieke2018-2018-01-23.xml
        finance/FinancialServices01/Nieke2018-2018-02-20.xml
        finance/FinancialServices01/Nieke2018-2018-03-26.xml
        finance/FinancialServices01/Nieke2018-2018-04-23.xml
        finance/FinancialServices01/Nieke2018-2018-05-09.xml
        automotive/automotive2/Knüppel2017-2_1.xml
        automotive/automotive2/Knüppel2017-2_2.xml
        automotive/automotive2/Knüppel2017-2_3.xml
        automotive/automotive2/Knüppel2017-2_4.xml
    )
    additional_model_files=()
    for url in "${additional_model_urls[@]}"; do
        local file=${url#finance/}
        file=${file#automotive/}
        file=${file//ü/ue}
        download-payload-file "$file" \
            "https://raw.githubusercontent.com/SoftVarE-Group/feature-model-benchmark/refs/heads/master/feature_models/original/$url"
        additional_model_files+=("$file")
    done
}

download-additional-models

experiment-systems() {
    case "$PASS" in
        main)
        add-axtls-kconfig-history
        add-buildroot-kconfig-history
        add-busybox-kconfig-history
        add-embtoolkit-kconfig-history
        add-freetz-ng-kconfig-history
        add-l4re-kconfig-history
        add-linux-kconfig-history
        add-toybox-kconfig-history
        add-uclibc-kconfig-history
        add-uclibc-ng-kconfig-history
        for file in "${additional_model_files[@]}"; do
            add-model-payload-file "$file"
        done
        ;;
        commits)
        add-busybox-kconfig-history-commits ;;
    esac
}

experiment-test-systems(__NO_CI__) {
    case "$PASS" in
        main)
        add-axtls-kconfig-history --from release-1.0.0 --to release-1.0.2 ;;
        commits) ;;
    esac
}

experiment-stages() {
    clone-systems
    local input
    if [[ "$PASS" == main ]]; then
        tag-linux-revisions
    elif [[ "$PASS" == commits ]]; then
        generate-busybox-models
        input=generate-busybox-models
    fi
    read-statistics --options skip-sloc --input "$input"

    extract-kconfig-models \
        --with-kconfigreader y \
        --with-kclause y \
        --date-prefix "$(date-format time)" \
        --input "$input"
    join-into read-statistics extract-kconfig-models

    remove-duplicate-files --file-field model_file
    compute-file-pairs --file-field model_file --group-field system
    diff-with-clausy \
        --file-field model_file \
        --timeout 300 \
        --attempts 3 \
        --group-field system
}
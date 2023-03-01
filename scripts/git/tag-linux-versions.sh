#!/bin/bash
# ./tag-linux-versions.sh
# adds Linux versions to the Linux Git repository
# creates an orphaned branch and tag for each version
# useful to add old versions before the first Git tag v2.6.12
# by default, tags all versions between 2.5.45 and 2.6.12, as these use Kconfig

add-system() {
    local system=$1
    require-value system
    if [[ $system == linux ]]; then
        if [[ ! -d $(input-directory)/linux ]]; then
            error "Linux has not been cloned yet. Please prepend a stage that runs clone-systems.sh."
        fi

        if git -C linux show-branch v2.6.11 2>&1 | grep -q "No revs to be shown."; then
            git -C linux tag -d v2.6.11 # delete non-commit 2.6.11
        fi

        # could also tag older versions, but none use Kconfig
        tag-versions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.5/ 2.5.45
        tag-versions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/ 2.6.0 2.6.12
        # could also add more granular versions with minor or patch level after 2.6.12, if necessary

        if [[ $dirty -eq 1 ]]; then
            git -C $(input-directory)/linux prune
            git -C $(input-directory)/linux gc
        fi
    fi
}

tag-versions() {
    local base_uri=$1
    local start_inclusive=$2
    local end_exclusive=$3
    require-value base_uri
    local versions=$(curl -s $base_uri | sed 's/.*>\(.*\)<.*/\1/g' | grep .tar.gz | cut -d- -f2 | sed 's/\.tar\.gz//' | sort -V \
        | ([[ -z $start_inclusive ]] && cat || sed -n '/'$start_inclusive'/,$p') \
        | ([[ -z $end_exclusive ]] && cat || sed -n '/'$end_exclusive'/q;p'))
    for version in ${versions[@]}; do
        if ! $(git -C $(input-directory)/linux tag | grep -q ^v$version$); then
            echo -n "Adding tag for Linux $version "
            local date=$(date -d "$(curl -s $base_uri | grep linux-$version.tar.gz | \
                cut -d'>' -f3 | tr -s ' ' | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)" +%s)
            echo "($(date -d@$date +"%Y-%m-%d")) ..."
            dirty=1
            wget -q $base_uri/linux-$version.tar.gz
            tar xzf *.tar.gz*
            pushd $(input-directory)/linux
            git reset -q --hard >/dev/null
            git clean -q -dfx >/dev/null
            git checkout -q --orphan $version >/dev/null
            git reset -q --hard >/dev/null
            git clean -q -dfx >/dev/null
            cp -R ../../linux-$version/. ./
            git add -A >/dev/null
            GIT_COMMITTER_DATE=$date git commit -q --date $date -m v$version >/dev/null
            git tag v$version >/dev/null
            popd
            rm -rf linux-$version
        else
            echo "Skipping tag for Linux $version"
        fi
    done
}

source main.sh load-subjects
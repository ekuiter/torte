#!/bin/bash

# Adds Linux versions to the Linux Git repository.
# Creates an orphaned branch and tag for each version.
# Useful to add old versions before the first Git tag v2.6.12.

cd input
if ! [[ -d linux ]]; then
    git clone https://github.com/torvalds/linux
fi
rm -f *.tar.gz*
if git -C linux show-branch v2.6.11 2>&1 | grep -q "No revs to be shown."; then
    git -C linux tag -d v2.6.11 # delete non-commit 2.6.11
fi

tag-unknown-versions() {
    base_uri=$1
    start_inclusive=$2
    end_exclusive=$3
    versions=$(curl -s $base_uri | sed 's/.*>\(.*\)<.*/\1/g' | grep .tar.gz | cut -d- -f2 | sed 's/\.tar\.gz//' | sort -V \
        | ([[ -z $start_inclusive ]] && cat || sed -n '/'$start_inclusive'/,$p') \
        | ([[ -z $end_exclusive ]] && cat || sed -n '/'$end_exclusive'/q;p'))
    for version in ${versions[@]}; do
        if ! $(git -C linux tag | grep -q ^v$version$); then
            echo -n "Adding tag for Linux $version "
            date=$(date -d "$(curl -s $base_uri | grep linux-$version.tar.gz | \
                cut -d'>' -f3 | tr -s ' ' | cut -d' ' -f2- | rev | cut -d' ' -f2- | rev)" +%s)
            echo "($(date -d@$date +"%Y-%m-%d")) ..."
            dirty=1
            wget -q --show-progress $base_uri/linux-$version.tar.gz
            tar xzf *.tar.gz*
            rm -f *.tar.gz*
            cd linux
            git reset -q --hard >/dev/null
            git clean -q -dfx >/dev/null
            git checkout -q --orphan $version >/dev/null
            git reset -q --hard >/dev/null
            git clean -q -dfx >/dev/null
            cp -R ../linux-$version/. ./
            git add -A >/dev/null
            GIT_COMMITTER_DATE=$date git commit -q --date $date -m v$version >/dev/null
            git tag v$version >/dev/null
            cd ..
            rm -rf linux-$version
        fi
    done
}

# could also tag older versions, but none use Kconfig
tag-unknown-versions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.5/ 2.5.45
tag-unknown-versions https://mirrors.edge.kernel.org/pub/linux/kernel/v2.6/ 2.6.0 2.6.12
# could also add more granular versions with minor or patch level after 2.6.12, if necessary

if [[ $dirty -eq 1 ]]; then
    git -C linux prune
    git -C linux gc
fi

cd ..
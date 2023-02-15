#!/bin/bash

source setup.sh

git-checkout busybox https://github.com/mirror/busybox
git-checkout linux https://github.com/torvalds/linux

if [ -z $NOT_IN_DOCKER ]; then
    # for tag in $(git -C input/busybox tag | grep -v pre | grep -v alpha | grep -v rc | sort -V); do
    #     run busybox https://github.com/mirror/busybox $tag scripts/kconfig/*.o Config.in
    # done

    linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
    run linux skip-model v2.6.12 scripts/kconfig/*.o arch/i386/Kconfig $linux_env

    # in old versions, use c-binding from 2.6.12
    for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/q;p'); do
    #for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.0/,$p' | sed -n '/2.6.4/q;p'); do
        run linux https://github.com/torvalds/linux $tag /home/output/c-bindings/linux/v2.6.12.$BINDING arch/i386/Kconfig $linux_env
    done

    for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/,$p'); do
        if git -C input/linux ls-tree -r $tag --name-only | grep -q arch/i386; then
            run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
        else
            run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
        fi
    done
fi

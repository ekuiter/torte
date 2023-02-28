# first, we define general experimental setup
# next, we define the models to analyze
# finally, we define and combine analysis stages

input_directory=input # path to system repositories
output_directory=output # path to resulting outputs, created if necessary
skip_docker_build= # y if building Docker images should be skipped, useful for loading imported images

run-experiment() {
    run-stage 1 git-cloc/Dockerfile $input_directory "./clone-systems.sh"
    run-stage 2 git-cloc/Dockerfile $input_directory "./tag-linux-versions.sh"
    run-stage 3 git-cloc/Dockerfile $input_directory "./read-statistics.sh"
}

# a version is sys,tag/revision,arch

#READERS="kconfigreader kclause" # Docker containers with Kconfig extractors
#READERS="kclause" # Docker containers with Kconfig extractors
#ANALYSES="void dead core" # analyses to run on feature models, see run-...-analysis functions
#ANALYSES="void" # analyses to run on feature models, see run-...-analysis functions
#N=
# ITERATIONS=1 # number of iterations
# TIMEOUT_TRANSFORM=180 # transformation timeout in seconds
# TIMEOUT_ANALYZE=1800 # analysis timeout in seconds
# RANDOM_SEED=2302101557 # seed for choosing core/dead features
# NUM_FEATURES=1 # number of randomly chosen core/dead features
# SKIP_ANALYSIS=n # whether to only extract and transform feature models, omitting an analysis
# MEMORY_LIMIT=128g # memory limit for Docker containers

# evaluated hierarchical feature models
#HIERARCHIES=""

# evaluated (#)SAT solvers
# we choose all winning SAT solvers in SAT competitions
# for #SAT, we choose the five fastest solvers as evaluated by Sundermann et al. 2021, found here: https://github.com/SoftVarE-Group/emse21-evaluation-sharpsat/tree/main/solvers
#SOLVERS="sharpsat-countAntom sharpsat-d4 sharpsat-dsharp sharpsat-ganak sharpsat-sharpSAT"
#SOLVERS="c2d d4 dpmc gpmc sharpsat-td-arjun1 sharpsat-td-arjun2 sharpsat-td twg"
#SOLVERS="d4"

add-system busybox https://github.com/mirror/busybox
add-system linux https://github.com/torvalds/linux

add-version linux v2.5.45
add-version linux v2.5.46

# todo: add-c-binding, add-feature-model; implying add-version

# for tag in $(git -C input/busybox tag | grep -v pre | grep -v alpha | grep -v rc | sort -V); do
#     run busybox https://github.com/mirror/busybox $tag scripts/kconfig/*.o Config.in
# done

linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
# run linux skip-model v2.6.12 scripts/kconfig/*.o arch/i386/Kconfig $linux_env

# # in old versions, use c-binding from 2.6.12
# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/q;p'); do
# #for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.0/,$p' | sed -n '/2.6.4/q;p'); do
#     run linux https://github.com/torvalds/linux $tag /home/output/c-bindings/linux/v2.6.12.$BINDING arch/i386/Kconfig $linux_env
# done

# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/,$p'); do
#     if git -C input/linux ls-tree -r $tag --name-only | grep -q arch/i386; then
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
#     else
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
#     fi
# done

# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.35/,$p' | sed -n '/2.6.37/q;p'); do
#     if git -C input/linux ls-tree -r $tag --name-only | grep -q arch/i386; then
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
#     else
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
#     fi
# done
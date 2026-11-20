#!/bin/bash

required_cpu_flags=(
    avx512f avx512dq avx512ifma avx512cd avx512bw avx512vl avx512vbmi
    avx512_vnni avx512_vbmi2 avx512_bitalg avx512_vpopcntdq
    gfni vaes vpclmulqdq
)
cpu_flags=$(grep -m1 '^flags' /proc/cpuinfo)
for flag in "${required_cpu_flags[@]}"; do
    if [[ $cpu_flags != *" $flag "* ]]; then
        echo "LymphoSAT's competition binary requires the AVX-512 feature set of Intel Ice Lake or newer." >&2
        exit 2
    fi
done

temporary_directory=$(mktemp -d)
trap 'rm -r -- "$temporary_directory"' EXIT

/home/lymphosat/solver/solver "$1" "$temporary_directory/proof.out"

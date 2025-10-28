#!/bin/bash
# helpers for working with DIMACS files

# returns the number of variables in a DIMACS file
dimacs-get-variable-number(file) {
    grep -E ^p "$file" | cut -d' ' -f3
}

# returns the number of clauses in a DIMACS file
dimacs-get-clause-number(file) {
    grep -E ^p "$file" | cut -d' ' -f4
}

# updates the number of clauses in a DIMACS file
dimacs-set-clause-number(file, clause_number) {
    sed -i "s/^\(p cnf [[:digit:]]\+ \)[[:digit:]]\+/\1$clause_number/" "$file"
}

# looks up the variable index for a given feature in a DIMACS file
dimacs-lookup-variable-index(file, feature) {
    # see src/docker/featjar/transform/src/main/java/KConfigReaderFormat.java
    feature=${feature//=/_}
    feature=${feature//:/_}
    feature=${feature//./_}
    feature=${feature//,/_}
    feature=${feature//\//_}
    feature=${feature//\\/ _}
    feature=${feature// /_}
    feature=${feature//-/_}
    grep -E '^c [0-9]+ '"$feature"'$' "$file" | cut -d' ' -f2
}

# appends an assumption for a feature to a DIMACS file
dimacs-assume(file, feature, polarity=) {
    local variable_index clause_number
    variable_index=$(dimacs-lookup-variable-index "$file" "$feature")
    if [[ -z $variable_index ]]; then
        error "Feature '$feature' not found in DIMACS file '$file'"
    fi
    clause_number=$(dimacs-get-clause-number "$file")
    clause_number=$((clause_number + 1))
    dimacs-set-clause-number "$file" "$clause_number"
    echo "$polarity$variable_index 0" >> "$file"
}
# computes the backbone of a DIMACS file (+ and - mark core and dead variables, respectively)
# (C) 2020  Jaroslav Šafář
# (C) 2023 Elias Kuiter
# adapted to rely on the performant SAT solver kissat_MAB-HyWalk (winner of the SAT Competition 2022)
# added several performance optimizations for analyzing large formulas
# also added functionality to remove backbone from DIMACS

import sys
import heapq
import subprocess
import shutil
import os
import tempfile
import argparse
import itertools

working_directory = '/'.join(sys.argv[0].split('/')[:-1])

def flatten(iterable):
    iterator = iter(iterable)
    try:
        while 1:
            item = next(iterator)
            if not hasattr(item,'__trunc__'):
                iterator = itertools.chain(iter(item), iterator)
            else:
                yield item
    except StopIteration:
        pass

def read_variable_map(file, by_name=False):
    f = open(file, mode="r")
    dimacs_formula = f.read()
    dimacs_formula = dimacs_formula.splitlines()
    variable_map = {}
    for s in dimacs_formula:
        if s.startswith('c '):
            parts = s[2:].strip().split()
            if by_name:
                variable_map[parts[1]] = int(parts[0])
            else:
                variable_map[int(parts[0])] = parts[1]
    f.close()
    return variable_map

def read_dimacs(file):
    global variables
    f = open(file, mode="r")
    dimacs_formula = f.read()
    dimacs_formula = dimacs_formula.splitlines()
    formula = [list(map(int, clause[:-2].strip().split())) for clause in dimacs_formula if clause != "" and
               clause[0] not in ["c", "p", "%", "0"]]
    variables = [(s.split()[2]) for s in dimacs_formula if s.startswith('p ')][0]
    f.close()
    return formula

def write_dimacs(file, formula, variable_map=None):
    global variables
    f = open(file, "w+")
    if variable_map:
        for index, variable in variable_map.items():
            f.write(f'c {index} {variable}\n')
    f.write(f'p cnf {variables} {len(formula)}\n')
    for c in formula:
        f.write(' '.join(map(str, c)) + ' 0\n')
    f.close()

def append_dimacs(from_file, to_file, literal):
    global variables
    from_file = open(from_file, mode="r")
    to_file = open(to_file, mode="w+")
    literals = int(from_file.readline().split()[3])
    to_file.write(f'p cnf {variables} {literals + 1}\n')
    shutil.copyfileobj(from_file, to_file)
    to_file.write(f'{literal} 0\n')
    from_file.close()
    to_file.close()

def shell(command):
    return subprocess.run(command, capture_output=True, text=True).stdout.split('\n')

def kissat(file):
    model = list(flatten([list(map(int, s[2:].strip().split())) for s in shell([f'{working_directory}/kissat_MAB-HyWalk', file]) if s.startswith('v ')]))
    return len(model) > 0, model

def delete(file):
    os.remove(file) if os.path.exists(file) else None

def find_backbone(file):
    with tempfile.TemporaryDirectory() as temp_directory:
        def temp_file(file):
            return f'{temp_directory}/{file}.dimacs'
        formula_file = temp_file('formula')
        assumed_file = temp_file('assumed')
        inferred_file = temp_file('inferred')
        
        formula = read_dimacs(file)
        write_dimacs(formula_file, formula)
        sat, model = kissat(formula_file)
        if not sat:
            return None, None

        occurrences = {}
        for clause in formula:
            for literal in clause:
                occurrences.setdefault(literal, 0)
                occurrences[literal] += 1

        def compare(self, a, b):
            return a[0] < b[0]
        heapq.cmp_lt=compare
        candidates = []
        for literal in model:
            heapq.heappush(candidates, [-occurrences.get(literal, 0), literal])

        backbone = []
        while candidates:
            _, literal = heapq.heappop(candidates)
            if literal == 0:
                continue
            append_dimacs(formula_file, assumed_file, -literal)
            sat, model = kissat(assumed_file)
            if not sat:
                backbone.append(literal)
                append_dimacs(formula_file, inferred_file, literal)
                os.rename(inferred_file, formula_file)
            else:
                temp = set(model)
                for c in candidates:
                    if c[1] not in temp:
                        c[1] = 0

        delete(formula_file)
        delete(assumed_file)
        delete(inferred_file)
        return backbone, formula

def clean_backbone(backbone, formula):
    backbone = set(backbone)
    new_formula = []
    
    for literal in backbone:
        new_formula.append([literal])

    for clause in formula:
        done = False
        for literal in backbone:
            if literal in clause:
                done = True
                break
        if done:
            continue
        new_clause = []
        for literal in clause:
            if -literal in backbone:
                continue
            new_clause.append(literal)
        new_formula.append(new_clause)

    return new_formula

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Computes and removes backbones.')
    parser.add_argument('--input', help='DIMACS input file', required=True)
    parser.add_argument('--backbone', help='backbone output file')
    parser.add_argument('--output', help='DIMACS output file')
    args = parser.parse_args()

    backbone, formula = find_backbone(args.input)
    variable_map = read_variable_map(args.input)

    if backbone:
        if args.backbone:
            readable_backbone = [('+' if l > 0 else '-') + (variable_map[abs(l)] if abs(l) in variable_map else str(abs(l))) for l in backbone]
            f = open(args.backbone, mode="w+")
            for literal in readable_backbone:
                f.write(literal + '\n')
            f.close()

        if args.output:
            new_formula = clean_backbone(backbone, formula)
            write_dimacs(args.output, new_formula, variable_map)
    
    else:
        print('formula unsatisfiable')
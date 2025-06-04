# computes the backbone of a DIMACS file (+ and - mark core and dead variables, respectively)
# uses https://github.com/arminbiere/cadiback and is more efficient than backbone_kissat.py

import subprocess
import os
import argparse
import itertools

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

def shell(command):
    return subprocess.run(command, capture_output=True, text=True).stdout.split('\n')

def cadiback(file):
    return list(flatten([list(map(int, s[2:].strip().split())) for s in shell([f'./cadiback', file]) if s.startswith('b ') and not s == 'b 0']))

def delete(file):
    os.remove(file) if os.path.exists(file) else None

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

    formula = read_dimacs(args.input)
    backbone = cadiback(args.input)
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
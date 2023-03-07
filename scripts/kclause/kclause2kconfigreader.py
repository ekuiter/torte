import pickle
import sys
import z3
import re
import collections
import io

with open(sys.argv[1], 'rb') as fp:
  kclause = pickle.load(fp)

kclause_constraints = {}
for var in kclause.keys():
  kclause_constraints[var] = [ z3.parse_smt2_string(clause) for clause in kclause[var] ]

constraints = []
for var in kclause_constraints.keys():
  for z3_clause in kclause_constraints[var]:
    constraints.extend(z3_clause)

_PP = z3.PP()
_PP.max_width = float('inf')
_PP.max_lines = float('inf')
_PP.max_indent = float('inf')
_Formatter = z3.Formatter()
_Formatter.max_depth = float('inf')
_Formatter.max_args = float('inf')
_Formatter.max_visited = float('inf')

def format(a):
    out = io.StringIO()
    _PP(out, _Formatter(a))
    return out.getvalue()

sexprs = [re.sub('\s', '', format(c))
  .strip()
  .replace(',', ' ')
  .replace('And(', '(and ')
  .replace('Or(', '(or ')
  .replace('Not(', '(not ') for c in constraints]
 
term_regex = r'''(?mx)
    \s*(?:
        (?P<brackl>\()|
        (?P<brackr>\))|
        (?P<num>\-?\d+\.\d+|\-?\d+)|
        (?P<sq>"[^"]*")|
        (?P<s>[^(^)\s]+)
       )'''
 
def parse_sexp(sexp):
    stack = []
    out = []
    for termtypes in re.finditer(term_regex, sexp):
        term, value = [(t,v) for t,v in termtypes.groupdict().items() if v][0]
        if   term == 'brackl':
            stack.append(out)
            out = []
        elif term == 'brackr':
            assert stack, "Trouble with nesting of brackets"
            tmpout, out = out, stack.pop(-1)
            out.append(tmpout)
        elif term == 'num':
            v = float(value)
            if v.is_integer(): v = int(v)
            out.append(v)
        elif term == 'sq':
            out.append(value[1:-1])
        elif term == 's':
            out.append(value)
        else:
            raise NotImplementedError("Error: %r" % (term, value))
    assert not stack, "Trouble with nesting of brackets"
    return out[0]

def flatten(l):
    for el in l:
        if isinstance(el, collections.abc.Iterable) and not isinstance(el, (str, bytes)):
            yield from flatten(el)
        else:
            yield el

def uniq(numbers):
    list_of_unique_numbers = []
    unique_numbers = set(numbers)
    for number in unique_numbers:
        list_of_unique_numbers.append(number)
    return list_of_unique_numbers

sexprs = [parse_sexp(sexpr) for sexpr in sexprs]
features = uniq([x for x in flatten(sexprs) if x not in ('not', 'and', 'or')])

def to_kconfigreader(sexpr):
  if isinstance(sexpr, str):
    return "def(" + sexpr + ")"
  if sexpr[0] == "and":
    return "(" + "&".join([to_kconfigreader(x) for x in sexpr[1:]]) + ")"
  if sexpr[0] == "or":
    return "(" + "|".join([to_kconfigreader(x) for x in sexpr[1:]]) + ")"
  if sexpr[0] == "not":
    return "!" + to_kconfigreader(sexpr[1])
  return "<unsupported>"

[print(to_kconfigreader(f)) for f in sexprs]
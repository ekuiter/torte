import sys
import z3

# The following is NOT the correct code to Tseitin-transform a Boolean formula into CNF:
# s = z3.Solver()
# g = z3.Goal()
# with open(sys.argv[1], 'rb') as fp:
#   g.add(z3.parse_smt2_string(fp.read()))
# s.add(g)
# print(s.dimacs())
# This is wrong because .dimacs() does not call the tseitin-cnf tactic. Even
# s = z3.Tactic("tseitin-cnf").solver()
# does not work, as the actual solver is not called by .dimacs().
# Instead, this produces a garbage CNF (see https://github.com/Z3Prover/z3/issues/6577).
# For a correct Tseitin transformation, use this script instead.

goal = z3.Goal()
with open(sys.argv[1], 'rb') as file:
  goal.add(z3.parse_smt2_string(file.read()))

# Since z3 v4.12.1, the simplifier must be called explictly with Then, so Tactic("tseitin-cnf") is not enough.
goal = z3.Then("simplify", "elim-and", "tseitin-cnf")(goal)[0]

# Print as DIMACS and rearrange comment lines to occur before the problem line (as expected by some solvers).
dimacs = goal.dimacs()
dimacs = dimacs[dimacs.find("c "):].strip() + "\n" + \
  dimacs[:dimacs.find("c ")].strip() + "\n"

with open(sys.argv[2], 'w') as file:
  file.write(dimacs)
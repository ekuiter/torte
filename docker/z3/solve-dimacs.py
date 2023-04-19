import sys
import z3

solver = z3.Solver()
solver.from_file(sys.argv[1])
result = str(solver.check())
print("SATISFIABLE" if result == "sat" else ("UNSATISFIABLE" if result == "unsat" else ""))
# printing a model is also possible:
# print(solver.model())
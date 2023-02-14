# cnf eval stuff

* todo: adapt readme from ASE'22 repo
* maybe re-add ASE and FM repo params configuration, also re-adding hierarchies and SAT solvers
* make configurable which cnf transformation is used for which source (currently only kcr - kcr, and kcl - z3, and no fide)
* make prepare_linux_repository.sh and extract.sh read its configuration from params.ini as well (single source of configuration)
* shiny name?
* upgrade featjar version
* integrate negation-cnf
* join results_analyze and transform.csv
* join warnings and errors
* update clean, export, etc scripts
* see https://github.com/paulgazz/kmax/blob/master/kmax/kextractlinux https://github.com/paulgazz/kmax/blob/master/kmax/arch.py for fixing linux >= 4.19
* rename stages
* abstract away stages for easier adding / changing / skipping of stages?
* clarify requirements of run.sh (vagrant?)

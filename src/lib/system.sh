#!/bin/bash
# convenience functions for defining systems

# generates boilerplate functions for a typical KConfig-based system
# always generates add-*-kconfig-revisions and add-*-kconfig-sample
# if kconfig_file and lkc_directory are given, also generates add-*-kconfig
# the system must already have add-*-system defined before the generated functions are called
define-system(system, kconfig_file=, lkc_directory=, lkc_target=, lkc_output_directory=, environment=, sample_branch=) {
    if [[ -n $kconfig_file ]] && [[ -n $lkc_directory ]]; then
        eval "$(compile-script <(cat <<- END
			add-${system}-kconfig(revision) {
			    add-${system}-system
			    if [[ ! -d \$(input-directory)/${system} ]]; then return; fi
			    add-revision --system ${system} --revision "\$revision"
			    add-kconfig --system ${system} --revision "\$revision" --kconfig-file "${kconfig_file}"  --lkc-directory "${lkc_directory}" --lkc-target "${lkc_target}" --lkc-output-directory "${lkc_output_directory}" --environment "${environment}"
			}
			END
        ))"
    fi

    eval "$(compile-script <(cat <<- END
		add-${system}-kconfig-revisions(revisions=) {
		    add-${system}-system
		    if [[ -z \$revisions ]]; then return; fi
		    local -a revisions_array
		    local revision
		    mapfile -t revisions_array < <(printf '%s\n' "\$revisions")
		    for revision in "\${revisions_array[@]}"; do
		        [[ -z \$revision ]] && continue
		        add-${system}-kconfig --revision "\$revision"
		    done
		}
		add-${system}-kconfig-sample(interval=) {
		    if [[ -z \$interval ]]; then interval=$(interval yearly); fi
		    add-${system}-kconfig-revisions "\$(memoize-global git-sample-commits ${system} "\$interval" ${sample_branch})"
		}
		END
    ))"
}

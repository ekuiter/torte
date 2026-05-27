#!/bin/bash
# convenience functions for defining systems

# generates boilerplate functions for a typical KConfig-based system
# always generates add-*-kconfig-revisions and add-*-kconfig-sample
# if kconfig_file and lkc_directory are given, also generates add-*-kconfig
# the system must already have add-*-system defined before the generated functions are called
define-system(system, kconfig_file=, lkc_directory=, lkc_output_directory=, sample_branch=) {
    if [[ -n $kconfig_file ]] && [[ -n $lkc_directory ]]; then
        eval "$(compile-script <(cat <<- END
			add-${system}-kconfig(revision) {
			    add-${system}-system
			    if [[ ! -d \$(input-directory)/${system} ]]; then return; fi
			    add-revision --system ${system} --revision "\$revision"
			    add-kconfig --system ${system} --revision "\$revision" --kconfig-file "${kconfig_file}" --lkc-directory "${lkc_directory}" --lkc-output-directory "${lkc_output_directory}"
			}
			END
        ))"
    fi

    eval "$(compile-script <(cat <<- END
		add-${system}-kconfig-revisions(revisions=) {
		    add-${system}-system
		    if [[ -z \$revisions ]]; then return; fi
		    while read -r revision; do
		        add-${system}-kconfig --revision "\$revision"
		    done < <(printf '%s\n' "\$revisions")
		}
		add-${system}-kconfig-sample(interval) {
		    add-${system}-kconfig-revisions "\$(memoize-global git-sample-revisions ${system} "\$interval" ${sample_branch})"
		}
		END
    ))"
}

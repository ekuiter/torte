#!/bin/bash
# stubs for API functions that are available to experiments

# defines the systems to investigate in the experiment
# this is a stub, users should define this in their experiment file
experiment-systems() {
    error "experiment-systems is not defined. Please define it in your experiment file."
}

# defines the stages of the experiment in order of their execution
# this is a stub, users should define this in their experiment file
experiment-stages() {
    error "experiment-stages is not defined. Please define it in your experiment file."
}

# adds a system
# implemented by library scripts (e.g., to clone a Git repository)
add-system(system, url=) {
    :
}

# adds a system revision
# implemented by library scripts (e.g., to read statistics)
add-revision(system, revision) {
    :
}

# adds a kconfig binding
# implemented by library scripts (e.g., to compile dumpconf or kextractor)
add-kconfig-binding(system, revision, kconfig_binding_files, environment=) {
    :
}

# adds a kconfig model
# implemented by library scripts (e.g., to read a kconfig model with kconfigreader or kclause)
add-kconfig-model(system, revision, kconfig_file, kconfig_binding_file=, environment=) {
    :
}

# adds a kconfig binding and model
add-kconfig(system, revision, kconfig_file, kconfig_binding_files, environment=) {
    :
}
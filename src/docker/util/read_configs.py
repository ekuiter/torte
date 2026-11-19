#!/usr/bin/env python3
"""Read Kconfig declarations and their immediate type declarations.

The git-grep mode reads matching blobs directly from a Git revision.  The
generated mode reads a checked-out working tree, including ignored and
untracked files created by the system's normal checkout preparation.
"""

import argparse
import csv
import re
import subprocess
from pathlib import Path


# matches declarations that start with ``config`` or ``menuconfig`` (allowing
# leading whitespace) and whose names contain only letters, digits, and underscores
# this approximation was manually inspected for Linux in the TOSEM'25 evaluation
# CONFIG_PATTERN uses POSIX character classes to find candidate files with ``git grep``
# CONFIG_RE validates the entire declaration to reject names containing illegal characters
CONFIG_PATTERN = r"^[[:space:]]*(menu)?config[[:space:]]+[0-9A-Za-z_]+"
CONFIG_RE = re.compile(r"^\s*(?:menu)?config\s+([0-9A-Za-z_]+)\s*(?:#.*)?$")

# conservatively recognizes one of Kconfig's five value types only when it
# occurs on the line immediately following a declaration
# declarations whose type occurs later are skipped rather than guessed
TYPE_RE = re.compile(r"(?:bool|tristate|string|int|hex)")


def run_git(repository, arguments):
    """Run Git in a repository and return its raw standard output."""
    result = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=False,
        stdout=subprocess.PIPE,
    )
    if result.returncode not in {0, 1}:
        raise subprocess.CalledProcessError(result.returncode, result.args)
    return result.stdout


def matching_files(repository, mode, revision, globs):
    """Return config-containing paths found by git grep in either input mode.

    The fast git-grep mode examines tracked blobs directly at the requested
    revision.  It requires no checkout, but cannot see files that a system
    generates during preparation.  Generated mode therefore reads the prepared
    working tree and deliberately includes ignored and untracked files.
    """
    if mode == "git-grep":
        arguments = ["grep", "-Ilz", "-E", CONFIG_PATTERN, revision, "--", *globs]
        prefix = f"{revision}:"
    else:
        arguments = [
            "grep",
            "--no-index",
            "--no-exclude-standard",
            "-Ilz",
            "-E",
            CONFIG_PATTERN,
            "--",
            *globs,
        ]
        prefix = ""
    entries = run_git(repository, arguments).decode("utf-8", errors="replace").split("\0")
    return [entry.removeprefix(prefix) for entry in entries if entry]


def git_blob_contents(repository, revision, paths):
    """Read many revision blobs efficiently through one git cat-file process."""
    process = subprocess.Popen(
        ["git", "-C", str(repository), "cat-file", "--batch"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    contents = {}
    try:
        for path in paths:
            process.stdin.write(f"{revision}:{path}\n".encode())
            process.stdin.flush()
            header = process.stdout.readline().decode("utf-8", errors="replace").rstrip("\n")
            _object, object_type, size = header.rsplit(" ", 2)
            if object_type != "blob":
                raise ValueError(f"Expected blob for {revision}:{path}, got {object_type}")
            contents[path] = process.stdout.read(int(size))
            process.stdout.read(1)
    finally:
        process.stdin.close()
        process.wait()
        process.stdout.close()
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, process.args)
    return contents


def working_tree_contents(repository, paths):
    """Read matching files from a generated working tree."""
    return {path: (repository / path).read_bytes() for path in paths}


def extract_rows(system, revision, contents):
    """Extract config names and immediate Kconfig types from each file."""
    configs = set()
    config_types = set()
    for path, raw_content in contents.items():
        lines = raw_content.decode("utf-8", errors="replace").splitlines()
        for index, line in enumerate(lines):
            match = CONFIG_RE.match(line)
            if not match:
                continue
            config = match.group(1)
            configs.add((system, revision, path, config))
            if index + 1 >= len(lines):
                continue
            type_match = TYPE_RE.search(lines[index + 1])
            if type_match:
                config_types.add((system, revision, path, config, type_match.group(0)))
    return sorted(configs), sorted(config_types)


def write_rows(path, header, rows):
    """Write deterministic CSV rows with a header."""
    with path.open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(header)
        writer.writerows(rows)


def main():
    """Read command-line inputs and produce config and type CSV fragments."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--system", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--mode", choices=["git-grep", "generated"], required=True)
    parser.add_argument("--configs-output", type=Path, required=True)
    parser.add_argument("--types-output", type=Path, required=True)
    parser.add_argument("globs", nargs="+")
    args = parser.parse_args()

    paths = matching_files(args.repository, args.mode, args.revision, args.globs)
    if args.mode == "git-grep":
        contents = git_blob_contents(args.repository, args.revision, paths)
    else:
        contents = working_tree_contents(args.repository, paths)
    configs, config_types = extract_rows(args.system, args.revision, contents)
    write_rows(args.configs_output, ["system", "revision", "kconfig_file", "config"], configs)
    write_rows(
        args.types_output,
        ["system", "revision", "kconfig_file", "config", "type"],
        config_types,
    )


if __name__ == "__main__":
    main()

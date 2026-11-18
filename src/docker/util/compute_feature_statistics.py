#!/usr/bin/env python3
"""Combine feature information produced by several experiment stages.

Assisted-by: LLM

The script treats ``(system, revision, architecture, extractor)`` as one model
observation.  For every observation it combines five kinds of input:

* the extracted model and its extractor-produced ``.features`` file;
* the system's known configuration options and their inferred Kconfig types;
* variables classified as unconstrained by a previous stage;
* the DIMACS variable map; and
* the signed backbone, whose positive/negative entries identify core/dead
  variables.

These sets are intersected to obtain the configurable, core, dead,
unconstrained, and constrained features.  The script then measures set sizes,
Jaccard similarities, changes between revisions, and agreement between
extractors.  It writes one primary CSV plus smaller diagnostic and lookup CSVs
to ``--output``.  The implementation is system-independent; Linux-specific
details, such as real architecture names and its config/type table, arrive in
the input-stage CSVs.

The command-line arguments point to stage directories, not individual files:

* ``--models/output.csv`` must contain ``system``, ``revision``, ``extractor``,
  and ``model_file``; each model file must have a sibling ``.features`` file;
* ``--configs/output.csv`` must contain ``system``, ``revision``, and
  ``config``; an optional ``output.types.csv`` adds ``type`` information;
* ``--unconstrained-features/output.csv`` maps ``model_file`` to
  ``unconstrained.features_file``;
* ``--backbone-dimacs/output.csv`` maps ``model_file`` to
  ``backbone.dimacs_file``; and
* ``--backbone-features/output.csv`` maps ``backbone.dimacs_file`` to
  ``backbone.features_file``.

The DIMACS input must be produced by the Z3 transformation.  Variable
classification relies on Z3's ``k!`` prefix for Tseitin auxiliaries and is not
valid for DIMACS files produced by other transformers.

All artifact paths in these CSVs are relative to their respective stage
directory.  Kconfig types are inferred generically for every system; declarations
that the config-reading stage cannot classify remain ``unknown``.  An architecture
is read only from an explicit ``architecture`` column; it is left empty when
architecture does not apply to the model.  Failed extraction rows whose
``model_file`` is empty or ends in ``NA`` are ignored because they have no feature
artifacts to summarize.

Output files:

* ``output.csv``: counts and similarities per model observation;
* ``output.extractor-comparison.csv``: agreement for matching extractors;
* ``output.configs-configurable.csv``: known configs with a configurable flag;
* ``output.feature-type-statistics.csv``: classifications grouped by type;
* ``output.potential-misses-*.csv``: diagnostic name mismatches; and
* ``output.metadata.csv``: input and output row counts.
"""

import argparse
import math
import re
from collections import defaultdict
from pathlib import Path

import pandas as pd


KCLAUSE_EXTRACTOR = "extract-kconfig-models-with-kclause"

# Columns of the per-model output.csv.  Empty strings represent unavailable
# measurements and are intentionally serialized as empty CSV cells.
COUNT_COLUMNS = [
    "#config_features",
    "#extracted_features",
    "#unconstrained_feature_variables",
    "#all_variables",
    "#variables",
    "#feature_variables",
    "#core_feature_variables",
    "#dead_feature_variables",
    "#constrained_feature_variables",
    "#undead_feature_variables",
    "#all_feature_variables",
    "#ALL_feature_variables",
    "#features",
    "#core_features",
    "#unconstrained_features",
    "#constrained_features",
    "#added_features",
    "#removed_features",
    "#total_features",
    "#total_added_features",
    "#total_removed_features",
]

STAT_COLUMNS = [
    "extracted_features_jaccard",
    "all_variables_jaccard",
    "variables_jaccard",
    "feature_variables_jaccard",
    "undead_feature_variables_jaccard",
    "all_feature_variables_jaccard",
    "features_jaccard",
    "unconstrained_bools",
    "unconstrained_tristates",
]


def require_columns(rows, required_columns, description):
    """Fail early with a useful error when an input stage has the wrong schema."""
    missing = set(required_columns) - set(rows[0])
    if missing:
        raise ValueError(f"Missing columns in {description}: {', '.join(sorted(missing))}")


def read_csv(path):
    """Read a stage CSV as string-valued dictionaries, or return no rows."""
    if not path.is_file():
        return []
    return pd.read_csv(path, dtype=str).fillna("").to_dict("records")


def read_required_csv(path, description, required_columns=()):
    """Read a stage CSV that must exist and contain at least one row."""
    rows = read_csv(path)
    if not rows:
        raise FileNotFoundError(f"Missing or empty {description}: {path}")
    require_columns(rows, required_columns, description)
    return rows


def write_csv(path, rows, fieldnames):
    """Write rows with a stable column order, creating the output directory."""
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows, columns=fieldnames).to_csv(path, index=False)


def read_features(path):
    """Read one feature per line and normalize an optional CONFIG_ prefix.

    Backbone files retain their ``+`` or ``-`` prefix because that polarity is
    required for core/dead classification.
    """
    if not path.is_file():
        return set()
    features = set()
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            feature = line.strip()
            if not feature:
                continue
            if feature.startswith("CONFIG_"):
                feature = feature[len("CONFIG_") :]
            features.add(feature)
    return features


def version_key(value):
    """Produce a natural-sort key so, for example, v10 follows v9."""
    return [int(part) if part.isdigit() else part for part in re.split(r"([0-9]+)", value or "")]


def jaccard(left, right):
    """Return intersection-over-union, or NaN when both sets are empty."""
    left = set(left)
    right = set(right)
    union = left | right
    return len(left & right) / len(union) if union else math.nan


def count_or_nan(features, minimum=2):
    """Return a set size or an empty CSV value when the set is unavailable."""
    if features is None or len(features) < minimum:
        return ""
    return len(features)


def replace_suffix(path, old_suffix, new_suffix):
    """Replace a known suffix while preserving the stage-relative path."""
    path = str(path)
    return path[: -len(old_suffix)] + new_suffix if path.endswith(old_suffix) else path + new_suffix


def load_artifact_mapping(stage_dir, csv_name, key_field, value_field):
    """Map source artifacts to derived artifacts using an exact stage schema."""
    mapping = {}
    rows = read_required_csv(
        stage_dir / csv_name,
        f"artifact map {stage_dir / csv_name}",
        (key_field, value_field),
    )
    for row in rows:
        key = row[key_field]
        mapped_value = row[value_field]
        if key and mapped_value and mapped_value != "NA":
            mapping[key] = mapped_value
    return mapping


def require_artifact_groups(groups, example_limit=3):
    """Reject stage CSVs that reference artifacts absent from their stage.

    A missing mapping is allowed because it represents an upstream operation
    that produced no output.  Once a CSV contains a non-NA artifact path,
    however, silently treating an absent file as an empty feature set would
    turn incomplete/pruned stage data into plausible but invalid statistics.
    """
    errors = []
    for description, stage_dir, relative_paths in groups:
        paths = list(dict.fromkeys(relative_paths))
        missing = [path for path in paths if not (stage_dir / path).is_file()]
        if missing:
            examples = ", ".join(str(path) for path in missing[:example_limit])
            if len(missing) > example_limit:
                examples += ", ..."
            errors.append(
                f"{description}: {len(missing)} of {len(paths)} missing "
                f"from {stage_dir} ({examples})"
            )
    if errors:
        raise FileNotFoundError("Missing referenced stage artifacts:\n- " + "\n- ".join(errors))


def read_dimacs_variables(path):
    """Split a Z3 DIMACS comment map into all, semantic, and feature variables.

    Z3's Tseitin auxiliaries (``k!``) are removed from the semantic set.
    Constants, comparison predicates, visibility helpers, and module companions
    are then removed to obtain the feature-variable set.
    """
    all_variable_map = {}
    variable_map = {}
    feature_variable_map = {}
    if not path or not path.is_file():
        return set(), set(), set()
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("c "):
                continue
            match = re.match(r"^c ([^ ]+) ([^ ]+)$", line.strip())
            if not match:
                continue
            index = int(match.group(1))
            name = match.group(2)
            all_variable_map[index] = name
            if "k!" not in name:
                variable_map[index] = name
                if (
                    name != "True"
                    and name != "<unsupported>"
                    and name != "PREDICATE_Compare"
                    and not name.startswith("__VISIBILITY__CONFIG_")
                    and not name.endswith("_MODULE")
                ):
                    feature_variable_map[index] = name
    return nontrivial_values(all_variable_map), nontrivial_values(variable_map), nontrivial_values(feature_variable_map)


def nontrivial_values(mapping):
    """Treat empty or one-entry variable maps as missing/degenerate data."""
    values = set(mapping.values())
    return set() if len(values) <= 1 else values


def load_config_data(config_rows, config_type_rows):
    """Index known configuration options and optional types by revision."""
    configs_by_revision = defaultdict(set)
    for row in config_rows:
        config = row.get("config", "")
        if not config:
            continue
        key = (row.get("system", ""), row.get("revision", ""))
        configs_by_revision[key].add(config)

    type_by_revision_config = {}
    for row in config_type_rows:
        config = row.get("config", "")
        if config:
            type_by_revision_config[(row.get("system", ""), row.get("revision", ""), config)] = row.get("type", "unknown") or "unknown"
    return configs_by_revision, type_by_revision_config


def build_configurable_rows(config_rows, total_features_by_revision):
    """Annotate every known config with whether any extractor found it."""
    rows = []
    for row in config_rows:
        system = row.get("system", "")
        revision = row.get("revision", "")
        config = row.get("config", "")
        output = dict(row)
        output["configurable"] = "true" if config in total_features_by_revision.get((system, revision), set()) else "false"
        rows.append(output)
    return rows


def build_type_statistics(config_type_rows, configurable_rows, feature_sets_by_system):
    """Aggregate config classifications by value type independently per system."""
    if not configurable_rows:
        return []

    keys = ["system", "revision", "config"]
    configured = pd.DataFrame(configurable_rows).drop_duplicates(keys, keep="last")
    if config_type_rows:
        config_types = pd.DataFrame(config_type_rows)[[*keys, "type"]].drop_duplicates(keys, keep="last")
        configured = configured.merge(config_types, on=keys, how="left", sort=False)
    else:
        configured["type"] = "unknown"
    configured["type"] = configured["type"].fillna("unknown").replace("", "unknown")

    for kind in ["unconstrained", "core", "dead"]:
        configured[kind] = [
            config in feature_sets_by_system.get(system, {}).get(kind, set())
            for system, config in zip(configured["system"], configured["config"])
        ]

    by_type = (
        configured.groupby(["system", "type"], sort=False, as_index=False)
        .agg(
            config=("config", "size"),
            core=("core", "sum"),
            dead=("dead", "sum"),
            unconstrained=("unconstrained", "sum"),
        )
    )
    by_type["constrained"] = (
        by_type["config"] - by_type["unconstrained"] - by_type["core"] - by_type["dead"]
    ).clip(lower=0)
    by_type["ratio"] = by_type["config"] / by_type.groupby("system")["config"].transform("sum")
    by_type = by_type.sort_values(["system", "config"], ascending=[True, False], kind="stable")

    rows = []
    for values in by_type.to_dict("records"):
        for variable in ["config", "core", "dead", "unconstrained", "constrained"]:
            rows.append(
                {
                    "system": values["system"],
                    "type": values["type"],
                    "ratio": "" if variable != "config" else f"      {round(values['ratio'] * 100, 2)}%",
                    "variable": variable,
                    "value": values[variable],
                }
            )
    return rows


def system_feature_rows(features_by_system, column="config"):
    """Turn system-scoped diagnostic sets into deterministic CSV rows."""
    return [
        {"system": system, column: feature}
        for system, features in sorted(features_by_system.items())
        for feature in sorted(features)
    ]


def revision_change_counts(total_features_by_revision_extractor):
    """Calculate revision-level additions and removals once per system/extractor."""
    revisions_by_extractor = defaultdict(list)
    for system, extractor, revision in total_features_by_revision_extractor:
        revisions_by_extractor[(system, extractor)].append(revision)

    changes = {}
    for (system, extractor), revisions in revisions_by_extractor.items():
        last_total = None
        for revision in sorted(revisions, key=version_key):
            current_total = total_features_by_revision_extractor[(system, extractor, revision)]
            added = current_total - last_total if last_total is not None else None
            removed = last_total - current_total if last_total is not None else None
            changes[(system, extractor, revision)] = (
                count_or_nan(added, 0),
                count_or_nan(removed, 0),
            )
            last_total = current_total
    return changes


def metadata_rows(*, model_rows, config_rows, config_type_rows, rows, comparable):
    """Record input and output row counts alongside the derived data."""
    return [
        {"key": "model_rows", "value": len(model_rows)},
        {"key": "config_rows", "value": len(config_rows)},
        {"key": "config_type_rows", "value": len(config_type_rows)},
        {"key": "feature_statistics_rows", "value": len(rows)},
        {"key": "extractor_comparison_rows", "value": len(comparable)},
    ]


def main():
    """Load stage artifacts, derive feature sets, aggregate them, and write CSVs."""
    parser = argparse.ArgumentParser(
        description="Combine extracted models, configs, DIMACS, and backbone data into feature statistics."
    )
    parser.add_argument(
        "--models",
        type=Path,
        required=True,
        help="extract-kconfig-models stage directory containing output.csv and model/.features files",
    )
    parser.add_argument(
        "--configs",
        type=Path,
        required=True,
        help="config-reading stage directory containing output.csv and optionally output.types.csv",
    )
    parser.add_argument(
        "--unconstrained-features",
        type=Path,
        required=True,
        help="compute-unconstrained-features stage directory",
    )
    parser.add_argument(
        "--backbone-dimacs",
        type=Path,
        required=True,
        help="transform-dimacs-to-backbone-dimacs stage directory containing Z3-produced DIMACS files",
    )
    parser.add_argument(
        "--backbone-features",
        type=Path,
        required=True,
        help="compute-backbone-features stage directory",
    )
    parser.add_argument(
        "--log-models",
        action="store_true",
        help="write start/end events for each processed model to stdout",
    )
    parser.add_argument("--output", type=Path, required=True, help="directory for the derived CSV files")
    args = parser.parse_args()

    # The model and config tables define the observations and the universe of
    # known configuration options.  The generic Kconfig reader infers types for
    # every system; declarations its regex cannot classify remain unknown.
    model_rows = read_required_csv(
        args.models / "output.csv",
        "model-stage CSV",
        ("system", "revision", "extractor", "model_file"),
    )
    model_rows = [
        row for row in model_rows
        if row["model_file"] and Path(row["model_file"]).name != "NA"
    ]
    if not model_rows:
        raise ValueError("Model-stage CSV contains no successful model files")
    # Build joins between artifacts using the relative paths stored in stage
    # CSVs.  Relative paths are important: every input stage is mounted under a
    # different directory when this script runs in a container.
    unconstrained_map = load_artifact_mapping(
        args.unconstrained_features,
        "output.csv",
        "model_file",
        "unconstrained.features_file",
    )
    backbone_map = load_artifact_mapping(
        args.backbone_features,
        "output.csv",
        "backbone.dimacs_file",
        "backbone.features_file",
    )
    backbone_dimacs_map = load_artifact_mapping(
        args.backbone_dimacs,
        "output.csv",
        "model_file",
        "backbone.dimacs_file",
    )

    model_files = [row["model_file"] for row in model_rows]
    require_artifact_groups(
        [
            ("model files", args.models, model_files),
            (
                "extractor feature files",
                args.models,
                [replace_suffix(path, Path(path).suffix, ".features") for path in model_files],
            ),
            ("unconstrained feature files", args.unconstrained_features, unconstrained_map.values()),
            ("backbone DIMACS files", args.backbone_dimacs, backbone_dimacs_map.values()),
            ("backbone feature files", args.backbone_features, backbone_map.values()),
        ]
    )

    # Load the large config tables only after artifact validation, so a pruned
    # or incomplete stage fails quickly rather than producing empty statistics.
    config_rows = read_required_csv(
        args.configs / "output.csv",
        "config-stage CSV",
        ("system", "revision", "config"),
    )
    config_type_rows = read_csv(args.configs / "output.types.csv")
    if config_type_rows:
        require_columns(
            config_type_rows,
            ("system", "revision", "config", "type"),
            "config-type CSV",
        )
    configs_by_revision, type_by_revision_config = load_config_data(config_rows, config_type_rows)

    # Accumulators serve three different aggregation levels:
    #   rows: one result per model/architecture/extractor;
    #   previous_features: changes from one revision to the next;
    #   total_*: unions over all architectures of a revision.
    rows = []
    extractor_comparison = {}
    potential_misses_grep = defaultdict(set)
    potential_misses_kmax = defaultdict(set)
    feature_sets_by_system = defaultdict(
        lambda: {"unconstrained": set(), "core": set(), "dead": set()}
    )
    previous_features = defaultdict(dict)
    total_features_by_revision_extractor = defaultdict(set)
    total_feature_variables_by_revision_extractor = defaultdict(set)

    # Sorting makes the "previous revision" calculation deterministic.  Each
    # system/extractor/architecture keeps its own evolution chain.
    model_rows.sort(
        key=lambda row: (
            row["system"],
            row["extractor"],
            version_key(row["revision"]),
            row.get("architecture", ""),
        )
    )
    for row in model_rows:
        system = row["system"]
        extractor = row["extractor"]
        revision = row["revision"]
        architecture = row.get("architecture", "")
        model_file = row["model_file"]
        if args.log_models:
            print(f"start\t{model_file}", flush=True)

        # config_features is the externally observed universe of valid config
        # names.  extracted_features is the extractor's direct feature list.
        config_features = configs_by_revision.get((system, revision), set())
        extracted_path = args.models / replace_suffix(model_file, Path(model_file).suffix, ".features")
        extracted_features = read_features(extracted_path)
        unconstrained_path = args.unconstrained_features / unconstrained_map.get(model_file, "")
        unconstrained_feature_variables = (
            read_features(unconstrained_path)
            if str(unconstrained_path) != str(args.unconstrained_features)
            else set()
        )

        # DIMACS comments provide the mapping from integer SAT variables back
        # to names.  The three returned sets successively remove auxiliaries and
        # non-feature names.
        dimacs_file = backbone_dimacs_map.get(model_file, "")
        dimacs_path = args.backbone_dimacs / dimacs_file if dimacs_file else None
        all_variables, variables, feature_variables = read_dimacs_variables(dimacs_path)

        # Signed backbone entries classify feature variables: positive means
        # core (always enabled), negative means dead (always disabled).
        backbone_file = backbone_map.get(dimacs_file, "")
        backbone_path = args.backbone_features / backbone_file if backbone_file else None
        raw_backbone = read_features(backbone_path) if backbone_path else set()
        core_feature_variables = {feature[1:] for feature in raw_backbone if feature.startswith("+")} & feature_variables
        dead_feature_variables = {feature[1:] for feature in raw_backbone if feature.startswith("-")} & feature_variables

        # The final feature set contains named config options that are either
        # represented by a live DIMACS variable or explicitly unconstrained.
        # Constrained features are the remainder after core and unconstrained
        # features have been separated.
        undead_feature_variables = feature_variables - dead_feature_variables
        all_feature_variables = undead_feature_variables | unconstrained_feature_variables
        features = all_feature_variables & config_features
        core_features = features & core_feature_variables
        unconstrained_features = features & unconstrained_feature_variables
        constrained_features = features - core_feature_variables - unconstrained_feature_variables
        feature_sets_by_system[system]["unconstrained"].update(unconstrained_features)
        feature_sets_by_system[system]["core"].update(core_features)
        feature_sets_by_system[system]["dead"].update(features & dead_feature_variables)

        # Type information is optional.  Missing entries fall into "unknown"
        # and therefore do not contribute to the bool/tristate columns.
        type_counts = defaultdict(int)
        for feature in unconstrained_features:
            type_counts[type_by_revision_config.get((system, revision, feature), "unknown")] += 1

        # Per-architecture evolution prevents a feature present only in one
        # architecture from being mistaken for a revision-level addition or
        # removal in another architecture.
        added_features = None
        removed_features = None
        previous = previous_features[(system, extractor)].get(architecture)
        if previous is not None:
            added_features = features - previous
            removed_features = previous - features
        previous_features[(system, extractor)][architecture] = features
        total_features_by_revision_extractor[(system, extractor, revision)].update(features)

        # The first extractor contributes a set; the second replaces that set
        # with their Jaccard agreement.  A remaining set later becomes an empty
        # value because no extractor comparison was possible.
        comparison_key = (system, revision, architecture)
        if comparison_key not in extractor_comparison:
            extractor_comparison[comparison_key] = features
        else:
            extractor_comparison[comparison_key] = jaccard(extractor_comparison[comparison_key], features)

        # KClause/Kmax-specific diagnostics expose names that occur on only one
        # side of the config-versus-model comparison.  They do not alter the
        # generic feature classification above.
        if extractor == KCLAUSE_EXTRACTOR:
            potential_misses_grep[system].update(
                feature for feature in all_feature_variables - features if "__CONFIG_" not in feature
            )
            total_feature_variables_by_revision_extractor[(system, extractor, revision)].update(
                feature_variables | unconstrained_feature_variables
            )

        # Similarities retain more information than counts: they show how close
        # each intermediate approximation is to the final configurable set.
        output = {
            "system": system,
            "extractor": extractor,
            "revision": revision,
            "architecture": architecture,
            "extracted_features_jaccard": jaccard(extracted_features, features),
            "all_variables_jaccard": jaccard(all_variables, features),
            "variables_jaccard": jaccard(variables, features),
            "feature_variables_jaccard": jaccard(feature_variables, features),
            "undead_feature_variables_jaccard": jaccard(undead_feature_variables, features),
            "all_feature_variables_jaccard": jaccard(all_feature_variables, features),
            "features_jaccard": 1 if features else "",
            "unconstrained_bools": type_counts["bool"],
            "unconstrained_tristates": type_counts["tristate"],
        }
        # Keep the actual sets only in memory; output.csv stores their sizes so
        # it remains compact enough for notebook analysis.
        sets = {
            "config_features": config_features,
            "extracted_features": extracted_features,
            "unconstrained_feature_variables": unconstrained_feature_variables,
            "all_variables": all_variables,
            "variables": variables,
            "feature_variables": feature_variables,
            "core_feature_variables": core_feature_variables,
            "dead_feature_variables": dead_feature_variables,
            "constrained_feature_variables": undead_feature_variables - core_feature_variables,
            "undead_feature_variables": undead_feature_variables,
            "all_feature_variables": all_feature_variables,
            "ALL_feature_variables": feature_variables | unconstrained_feature_variables,
            "features": features,
            "core_features": core_features,
            "unconstrained_features": unconstrained_features,
            "constrained_features": constrained_features,
            "added_features": added_features,
            "removed_features": removed_features,
        }
        for name, values in sets.items():
            output[f"#{name}"] = count_or_nan(values, 0 if name in {"added_features", "removed_features"} else 1)
        rows.append(output)
        if args.log_models:
            print(f"end\t{model_file}", flush=True)

    # Add architecture unions after all model rows of a revision are known.
    for row in rows:
        total_features = total_features_by_revision_extractor[(row["system"], row["extractor"], row["revision"])]
        row["#total_features"] = count_or_nan(total_features, 1)

    # Compute additions/removals again at revision level, this time over the
    # union of architectures rather than one architecture at a time.
    total_changes = revision_change_counts(total_features_by_revision_extractor)
    for row in rows:
        added, removed = total_changes[(row["system"], row["extractor"], row["revision"])]
        row["#total_added_features"] = added
        row["#total_removed_features"] = removed

    # Report known configs absent from Kmax's complete variable union.  These
    # are diagnostics for investigation, not automatically extraction errors.
    for (system, revision), config_features in configs_by_revision.items():
        kmax_variables = total_feature_variables_by_revision_extractor.get(
            (system, KCLAUSE_EXTRACTOR, revision), set()
        )
        if kmax_variables:
            potential_misses_kmax[system].update(config_features - kmax_variables)

    # Flatten the extractor-agreement accumulator into a stable CSV table.
    comparable = [
        {
            "system": system,
            "revision": revision,
            "architecture": architecture,
            "extractor_jaccard": "" if isinstance(value, set) else value,
        }
        for (system, revision, architecture), value in sorted(
            extractor_comparison.items(),
            key=lambda item: (item[0][0], version_key(item[0][1]), item[0][2]),
        )
    ]

    # A config is marked configurable if at least one extractor/architecture
    # includes it.  The resulting table supports config- and type-level plots.
    total_features_by_revision = defaultdict(set)
    for (system, _extractor, revision), values in total_features_by_revision_extractor.items():
        total_features_by_revision[(system, revision)].update(values)
    configurable_rows = build_configurable_rows(config_rows, total_features_by_revision)
    type_rows = build_type_statistics(config_type_rows, configurable_rows, feature_sets_by_system)

    # output.csv is the main per-model table.  The remaining files are focused
    # tables used by specific notebook analyses or to diagnose missing names.
    write_csv(args.output / "output.csv", rows, ["system", "extractor", "revision", "architecture", *STAT_COLUMNS, *COUNT_COLUMNS])
    write_csv(args.output / "output.extractor-comparison.csv", comparable, ["system", "revision", "architecture", "extractor_jaccard"])
    write_csv(args.output / "output.potential-misses-grep.csv", system_feature_rows(potential_misses_grep), ["system", "config"])
    write_csv(args.output / "output.potential-misses-kmax.csv", system_feature_rows(potential_misses_kmax), ["system", "config"])
    write_csv(args.output / "output.configs-configurable.csv", configurable_rows, [*config_rows[0].keys(), "configurable"] if config_rows else ["configurable"])
    write_csv(args.output / "output.feature-type-statistics.csv", type_rows, ["system", "type", "ratio", "variable", "value"])
    write_csv(
        args.output / "output.metadata.csv",
        metadata_rows(
            model_rows=model_rows,
            config_rows=config_rows,
            config_type_rows=config_type_rows,
            rows=rows,
            comparable=comparable,
        ),
        ["key", "value"],
    )


if __name__ == "__main__":
    main()

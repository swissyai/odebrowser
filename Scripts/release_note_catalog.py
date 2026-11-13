#!/usr/bin/env python3
"""Validate Ode's explicit, history-stable release-note catalog."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import pathlib
import re
import subprocess
import sys
from typing import Optional


CATALOG_PATH = "Documentation/ReleaseNotes.json"
LEGACY_SCHEMA_VERSION = 1
SCHEMA_VERSION = 2
SUPPORTED_CATEGORIES = ("new", "improved", "fixed", "removed", "internal")
REMOVED_CATEGORY = "removed"
# A removal names what replaces it, or says in exactly these words that nothing does.
NO_REPLACEMENT = "no replacement"
NOT_A_REPLACEMENT = {"none", "n/a", "nothing", "-", NO_REPLACEMENT}
PUBLICATION_CHANNELS = ("stable", "development", "nightly")
ENTRY_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class CatalogValidationError(ValueError):
    """The release-note catalog does not satisfy its repository contract."""


@dataclass(frozen=True)
class ReleaseNoteEntry:
    identifier: str
    category: str
    message: str
    # Only a removed entry carries these: what replaces the removed behavior,
    # or NO_REPLACEMENT, and the first version without it.
    replacement: Optional[str] = None
    removed_in: Optional[str] = None


@dataclass(frozen=True)
class ReleaseNoteCatalog:
    schema_version: int
    publication_baselines: dict[str, str]
    entries: dict[str, ReleaseNoteEntry]


def unique_json_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise CatalogValidationError(f"duplicate JSON key '{key}'")
        value[key] = item
    return value


def parse_version(version: str) -> tuple[int, int, int]:
    """An X.Y.Z marketing version as comparable numbers."""
    match = VERSION.fullmatch(version)
    if match is None:
        raise CatalogValidationError(f"'{version}' is not an X.Y.Z version")
    major, minor, patch = (int(part) for part in match.groups())
    return major, minor, patch


def one_trimmed_line(value: object) -> bool:
    return (
        isinstance(value, str)
        and bool(value.strip())
        and value == value.strip()
        and "\n" not in value
        and "\r" not in value
    )


def parse_entry(identifier: str, raw_entry: object, entry_source: str) -> ReleaseNoteEntry:
    if not isinstance(raw_entry, dict):
        raise CatalogValidationError(f"{entry_source}: must be an object")
    category = raw_entry.get("category")
    if category not in SUPPORTED_CATEGORIES:
        supported = ", ".join(SUPPORTED_CATEGORIES)
        raise CatalogValidationError(f"{entry_source}: category must be one of {supported}")
    if category == REMOVED_CATEGORY:
        if set(raw_entry) != {"category", "message", "replacement", "removedIn"}:
            raise CatalogValidationError(
                f"{entry_source}: a removed entry must contain only category, message, "
                "replacement and removedIn"
            )
    elif set(raw_entry) != {"category", "message"}:
        raise CatalogValidationError(f"{entry_source}: must contain only category and message")

    message = raw_entry["message"]
    if not isinstance(message, str) or not message.strip():
        raise CatalogValidationError(f"{entry_source}: message must be non-empty text")
    if not one_trimmed_line(message):
        raise CatalogValidationError(f"{entry_source}: message must be one trimmed line")
    if category != REMOVED_CATEGORY:
        return ReleaseNoteEntry(identifier, category, message)

    replacement = raw_entry["replacement"]
    if not one_trimmed_line(replacement) or (
        replacement.casefold() in NOT_A_REPLACEMENT and replacement != NO_REPLACEMENT
    ):
        raise CatalogValidationError(
            f"{entry_source}: replacement must name what replaces the removed behavior "
            f"in one trimmed line, or be exactly '{NO_REPLACEMENT}'"
        )
    removed_in = raw_entry["removedIn"]
    if not isinstance(removed_in, str) or VERSION.fullmatch(removed_in) is None:
        raise CatalogValidationError(
            f"{entry_source}: removedIn must be the X.Y.Z version from which the "
            "behavior is gone"
        )
    return ReleaseNoteEntry(identifier, category, message, replacement, removed_in)


def catalog_fields(schema_version: object, source: str) -> set[str]:
    """The fields a catalog of `schema_version` holds, each of them required."""
    if schema_version == LEGACY_SCHEMA_VERSION:
        return {"schemaVersion", "entries"}
    if schema_version == SCHEMA_VERSION:
        return {"schemaVersion", "publicationBaselines", "entries"}
    raise CatalogValidationError(
        f"{source}: schemaVersion must be {LEGACY_SCHEMA_VERSION} or {SCHEMA_VERSION}"
    )


def parse_entries(raw_entries: object, source: str) -> dict[str, ReleaseNoteEntry]:
    if not isinstance(raw_entries, dict):
        raise CatalogValidationError(f"{source}: entries must be an object")
    entries: dict[str, ReleaseNoteEntry] = {}
    for identifier, raw_entry in raw_entries.items():
        entry_source = f"{source}: entry '{identifier}'"
        if not ENTRY_ID.fullmatch(identifier) or len(identifier) > 80:
            raise CatalogValidationError(
                f"{entry_source}: id must be a lowercase kebab-case value up to 80 characters"
            )
        entries[identifier] = parse_entry(identifier, raw_entry, entry_source)
    return entries


def parse_publication_baselines(
    raw_baselines: object, entries: dict[str, ReleaseNoteEntry], source: str
) -> dict[str, str]:
    """Each channel's publication baseline, an entry the catalog holds."""
    if not isinstance(raw_baselines, dict) or set(raw_baselines) != set(PUBLICATION_CHANNELS):
        channels = ", ".join(PUBLICATION_CHANNELS)
        raise CatalogValidationError(
            f"{source}: publicationBaselines must contain exactly {channels}"
        )
    publication_baselines: dict[str, str] = {}
    for channel in PUBLICATION_CHANNELS:
        marker = raw_baselines[channel]
        if not isinstance(marker, str) or marker not in entries:
            raise CatalogValidationError(
                f"{source}: {channel} publication baseline '{marker}' "
                "must identify a catalog entry"
            )
        publication_baselines[channel] = marker
    return publication_baselines


def parse_catalog_document(contents: str, source: str) -> ReleaseNoteCatalog:
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error

    if not isinstance(document, dict):
        raise CatalogValidationError(f"{source}: catalog root must be an object")
    schema_version = document.get("schemaVersion")
    required_fields = catalog_fields(schema_version, source)
    if set(document) != required_fields:
        required = ", ".join(required_fields)
        raise CatalogValidationError(
            f"{source}: schemaVersion {schema_version} catalog must contain only {required}"
        )

    entries = parse_entries(document["entries"], source)
    publication_baselines: dict[str, str] = {}
    if schema_version == SCHEMA_VERSION:
        publication_baselines = parse_publication_baselines(
            document["publicationBaselines"], entries, source
        )
    return ReleaseNoteCatalog(schema_version, publication_baselines, entries)


def git_file(repository_root: pathlib.Path, object_name: str) -> Optional[str]:
    result = subprocess.run(
        ["git", "-C", str(repository_root), "show", object_name],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout
    return None


def working_catalog(repository_root: pathlib.Path) -> dict[str, ReleaseNoteEntry]:
    return working_catalog_document(repository_root).entries


def working_catalog_document(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    catalog_path = repository_root / CATALOG_PATH
    if not catalog_path.is_file():
        raise CatalogValidationError(f"{CATALOG_PATH} is missing")
    return parse_catalog_document(catalog_path.read_text(), CATALOG_PATH)


def staged_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    contents = git_file(repository_root, f":{CATALOG_PATH}")
    if contents is None:
        raise CatalogValidationError(f"stage {CATALOG_PATH} with the current commit")
    return parse_catalog_document(contents, f"staged {CATALOG_PATH}")


def head_catalog(repository_root: pathlib.Path) -> ReleaseNoteCatalog:
    contents = git_file(repository_root, f"HEAD:{CATALOG_PATH}")
    if contents is None:
        return ReleaseNoteCatalog(LEGACY_SCHEMA_VERSION, {}, {})
    return parse_catalog_document(contents, f"HEAD {CATALOG_PATH}")


def validate_removal_versions(
    entries: dict[str, ReleaseNoteEntry],
    marketing_version: str,
    added_entries: tuple[str, ...] = (),
) -> None:
    """No removal is from a version later than the current one, and a removal
    the commit adds is gone from the version that commit sets."""
    current = parse_version(marketing_version)
    for identifier, entry in entries.items():
        if entry.removed_in is None:
            continue
        if identifier in added_entries and entry.removed_in != marketing_version:
            raise CatalogValidationError(
                f"removed entry '{identifier}' must carry removedIn {marketing_version}, "
                f"the version this commit sets, not {entry.removed_in}"
            )
        if parse_version(entry.removed_in) > current:
            raise CatalogValidationError(
                f"removed entry '{identifier}' is gone from {entry.removed_in}, "
                f"later than the current version {marketing_version}"
            )


def validate_staged_entry(
    repository_root: pathlib.Path, marketing_version: Optional[str] = None
) -> tuple[str, ...]:
    previous_catalog = head_catalog(repository_root)
    current_catalog = staged_catalog(repository_root)
    previous_entries = previous_catalog.entries
    current_entries = current_catalog.entries
    deleted_entries = tuple(sorted(previous_entries.keys() - current_entries.keys()))
    if deleted_entries:
        deleted = ", ".join(deleted_entries)
        raise CatalogValidationError(
            f"catalog commits must not delete release-note entries: {deleted}"
        )

    rewritten_entries = tuple(
        identifier
        for identifier, entry in previous_entries.items()
        if current_entries.get(identifier) != entry
    )
    if rewritten_entries:
        rewritten = ", ".join(rewritten_entries)
        raise CatalogValidationError(
            f"catalog commits must not rewrite release-note entries: {rewritten}"
        )

    if current_catalog.schema_version < previous_catalog.schema_version:
        raise CatalogValidationError("catalog commits must not downgrade schemaVersion")

    previous_order = tuple(previous_entries)
    current_order = tuple(current_entries)
    is_version_two_migration = (
        previous_catalog.schema_version == LEGACY_SCHEMA_VERSION
        and current_catalog.schema_version == SCHEMA_VERSION
    )
    if not is_version_two_migration and current_order[: len(previous_order)] != previous_order:
        raise CatalogValidationError(
            "append new release-note entries after the existing catalog order"
        )

    added_entries = tuple(
        identifier for identifier in current_entries if identifier not in previous_entries
    )
    if not added_entries:
        raise CatalogValidationError(
            f"stage at least one new release-note entry in {CATALOG_PATH}"
        )
    if marketing_version is not None:
        validate_removal_versions(current_entries, marketing_version, added_entries)
    return added_entries


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--require-staged-entry", action="store_true")
    parser.add_argument(
        "--marketing-version",
        help="the checkout's X.Y.Z version, which no removal may be later than and "
        "which a staged removal must carry",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.require_staged_entry:
            added_entries = validate_staged_entry(
                arguments.repository_root, arguments.marketing_version
            )
            print(f"Validated new release-note entries: {', '.join(added_entries)}")
            return 0

        entries = working_catalog(arguments.repository_root)
        if arguments.marketing_version is not None:
            validate_removal_versions(entries, arguments.marketing_version)
        print(f"Validated {len(entries)} release-note entries.")
        return 0
    except (CatalogValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Contract coverage for Ode's explicit release-note catalog."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_SCRIPT = REPOSITORY_ROOT / "Scripts" / "release_note_catalog.py"
sys.path.insert(0, str(CATALOG_SCRIPT.parent))
import release_note_catalog  # noqa: E402


class ReleaseNoteCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository = pathlib.Path(self.temporary_directory.name)
        subprocess.run(
            ["git", "init", "--initial-branch=main"],
            cwd=self.repository,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Ode Tests"],
            cwd=self.repository,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.email", "tests@example.invalid"],
            cwd=self.repository,
            check=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_catalog(
        self,
        entries: dict[str, dict[str, str]],
        publication_baselines: dict[str, str] | None = None,
    ) -> None:
        catalog = self.repository / "Documentation" / "ReleaseNotes.json"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        document: dict[str, object] = {
            "schemaVersion": 1,
            "entries": entries,
        }
        if publication_baselines is not None:
            document = {
                "schemaVersion": 2,
                "publicationBaselines": publication_baselines,
                "entries": entries,
            }
        catalog.write_text(
            json.dumps(document, indent=2) + "\n"
        )

    def run_catalog_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "python3",
                str(CATALOG_SCRIPT),
                "--repository-root",
                str(self.repository),
                *arguments,
            ],
            cwd=self.repository,
            check=False,
            capture_output=True,
            text=True,
        )

    def commit_catalog(self) -> None:
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )
        subprocess.run(
            ["git", "commit", "-m", "catalog baseline"],
            cwd=self.repository,
            check=True,
            capture_output=True,
        )

    def stage_catalog(self) -> None:
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

    @staticmethod
    def removal(removed_in: str, replacement: str = "the Archive view") -> dict[str, str]:
        return {
            "category": "removed",
            "message": "The old archive list is gone.",
            "replacement": replacement,
            "removedIn": removed_in,
        }

    def test_valid_catalog_accepts_all_supported_categories(self) -> None:
        entries: dict[str, dict[str, str]] = {
            category: {
                "category": category,
                "message": f"Describe the {category} change clearly",
            }
            for category in ("new", "improved", "fixed", "internal")
        }
        entries["removed"] = self.removal("0.9.4")
        self.write_catalog(entries)

        result = self.run_catalog_check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Validated 5 release-note entries", result.stdout)

    def test_removed_entries_name_a_replacement_and_the_version_they_are_gone_from(
        self,
    ) -> None:
        self.write_catalog(
            {
                "replaced": self.removal("0.9.4"),
                "not-replaced": self.removal("0.9.4", "no replacement"),
            }
        )
        valid = self.run_catalog_check()
        self.assertEqual(valid.returncode, 0, valid.stderr)

        missing_replacement = self.removal("0.9.4")
        missing_replacement.pop("replacement")
        missing_version = self.removal("0.9.4")
        missing_version.pop("removedIn")
        invalid_entries = {
            "no replacement field": missing_replacement,
            "no version field": missing_version,
            "empty replacement": self.removal("0.9.4", ""),
            "a none word for no replacement": self.removal("0.9.4", "None"),
            "a recased no replacement": self.removal("0.9.4", "No replacement"),
            "two-part version": self.removal("0.9"),
            "suffixed version": self.removal("0.9.4-beta"),
            "replacement on a fix": {
                "category": "fixed",
                "message": "Describe a valid fix",
                "replacement": "the Archive view",
            },
            "version on a feature": {
                "category": "new",
                "message": "Describe a valid feature",
                "removedIn": "0.9.4",
            },
        }
        for case, entry in invalid_entries.items():
            with self.subTest(case=case):
                self.write_catalog({"entry": entry})
                result = self.run_catalog_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("entry 'entry'", result.stderr)

    def test_a_removal_is_never_from_a_version_later_than_the_current_one(self) -> None:
        self.write_catalog({"removal": self.removal("0.9.4")})

        for version, accepted in (("0.9.3", False), ("0.9.4", True), ("0.10.0", True)):
            with self.subTest(marketing_version=version):
                result = self.run_catalog_check("--marketing-version", version)
                self.assertEqual(result.returncode == 0, accepted, result.stderr)
                if not accepted:
                    self.assertIn("later than the current version", result.stderr)

    def test_a_staged_removal_is_gone_from_the_version_its_commit_sets(self) -> None:
        self.write_catalog({"earlier-removal": self.removal("0.9.1")})
        self.commit_catalog()

        self.write_catalog(
            {
                "earlier-removal": self.removal("0.9.1"),
                "new-removal": self.removal("0.9.4"),
            }
        )
        self.stage_catalog()

        stale = self.run_catalog_check(
            "--require-staged-entry", "--marketing-version", "0.9.5"
        )
        self.assertNotEqual(stale.returncode, 0)
        self.assertIn("new-removal", stale.stderr)
        self.assertIn("0.9.5", stale.stderr)

        current = self.run_catalog_check(
            "--require-staged-entry", "--marketing-version", "0.9.4"
        )
        self.assertEqual(current.returncode, 0, current.stderr)
        self.assertIn("new-removal", current.stdout)

    def test_version_two_catalog_requires_a_valid_baseline_for_each_channel(self) -> None:
        entries = {
            "stable-boundary": {
                "category": "internal",
                "message": "Record the stable publication boundary",
            },
            "development-boundary": {
                "category": "internal",
                "message": "Record the development publication boundary",
            },
            "nightly-boundary": {
                "category": "internal",
                "message": "Record the nightly publication boundary",
            },
        }
        valid_baselines = {
            "stable": "stable-boundary",
            "development": "development-boundary",
            "nightly": "nightly-boundary",
        }

        self.write_catalog(entries, valid_baselines)
        valid = self.run_catalog_check()
        self.assertEqual(valid.returncode, 0, valid.stderr)

        for invalid_baselines in (
            {"stable": "stable-boundary", "nightly": "nightly-boundary"},
            valid_baselines | {"preview": "nightly-boundary"},
            valid_baselines | {"nightly": "missing-entry"},
        ):
            with self.subTest(invalid_baselines=invalid_baselines):
                self.write_catalog(entries, invalid_baselines)
                invalid = self.run_catalog_check()
                self.assertNotEqual(invalid.returncode, 0)

    def test_catalog_rejects_unknown_fields_categories_and_invalid_ids(self) -> None:
        invalid_catalogs = (
            {
                "Bad ID": {
                    "category": "new",
                    "message": "Add a valid feature description",
                }
            },
            {
                "valid-id": {
                    "category": "changed",
                    "message": "Describe an unsupported category",
                }
            },
            {
                "valid-id": {
                    "category": "fixed",
                    "message": "Describe a valid fix",
                    "commit": "impossible-self-reference",
                }
            },
        )

        for entries in invalid_catalogs:
            with self.subTest(entries=entries):
                self.write_catalog(entries)
                result = self.run_catalog_check()
                self.assertNotEqual(result.returncode, 0)

    def test_staged_contract_requires_a_new_entry_and_preserves_existing_ids(self) -> None:
        entries = {
            "existing-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(entries)
        self.commit_catalog()

        no_change = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(no_change.returncode, 0)
        self.assertIn("stage at least one new release-note entry", no_change.stderr)

        entries["new-change"] = {
            "category": "improved",
            "message": "Make the current workflow easier to understand",
        }
        self.write_catalog(entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        added = self.run_catalog_check("--require-staged-entry")
        self.assertEqual(added.returncode, 0, added.stderr)
        self.assertIn("new-change", added.stdout)

        entries.pop("existing-change")
        self.write_catalog(entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        deleted = self.run_catalog_check("--require-staged-entry")
        self.assertNotEqual(deleted.returncode, 0)
        self.assertIn("must not delete release-note entries", deleted.stderr)

    def test_staged_contract_appends_new_ids_after_the_existing_catalog(self) -> None:
        existing_entries = {
            "existing-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(existing_entries)
        self.commit_catalog()

        inserted_entries = {
            "new-change": {
                "category": "new",
                "message": "Add a new workflow",
            },
            **existing_entries,
        }
        self.write_catalog(inserted_entries)
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        result = self.run_catalog_check("--require-staged-entry")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("append new release-note entries", result.stderr)

    def test_schema_two_migration_may_backfill_around_preserved_version_one_entries(self) -> None:
        existing_entries = {
            "later-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(existing_entries)
        self.commit_catalog()

        migrated_entries = {
            "stable-boundary": {
                "category": "internal",
                "message": "Record the stable publication boundary",
            },
            **existing_entries,
            "nightly-boundary": {
                "category": "internal",
                "message": "Record the nightly publication boundary",
            },
        }
        self.write_catalog(
            migrated_entries,
            {
                "stable": "stable-boundary",
                "development": "stable-boundary",
                "nightly": "nightly-boundary",
            },
        )
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        result = self.run_catalog_check("--require-staged-entry")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("stable-boundary", result.stdout)
        self.assertIn("nightly-boundary", result.stdout)

    def test_schema_migration_must_not_rewrite_an_existing_entry(self) -> None:
        existing_entries = {
            "existing-change": {
                "category": "fixed",
                "message": "Keep existing behavior reliable",
            }
        }
        self.write_catalog(existing_entries)
        self.commit_catalog()

        rewritten_entries = {
            "stable-boundary": {
                "category": "internal",
                "message": "Record the stable publication boundary",
            },
            "existing-change": {
                "category": "improved",
                "message": "Rewrite existing release copy",
            },
        }
        self.write_catalog(
            rewritten_entries,
            {
                "stable": "stable-boundary",
                "development": "stable-boundary",
                "nightly": "stable-boundary",
            },
        )
        subprocess.run(
            ["git", "add", "Documentation/ReleaseNotes.json"],
            cwd=self.repository,
            check=True,
        )

        result = self.run_catalog_check("--require-staged-entry")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must not rewrite release-note entries", result.stderr)


class CatalogDocumentTests(unittest.TestCase):
    """Which refusal a catalog document gets, checked in the order a reader meets it."""

    ENTRY = {"category": "fixed", "message": "Downloads resume."}
    BASELINES = {"stable": "first", "development": "first", "nightly": "first"}

    def refusal(self, document: object) -> str:
        contents = document if isinstance(document, str) else json.dumps(document)
        with self.assertRaises(release_note_catalog.CatalogValidationError) as refused:
            release_note_catalog.parse_catalog_document(contents, "notes.json")
        return str(refused.exception)

    def test_each_document_refusal_names_the_first_problem(self) -> None:
        entries = {"first": self.ENTRY}
        version_two = {"schemaVersion": 2, "publicationBaselines": self.BASELINES, "entries": entries}
        cases = (
            ("{", "notes.json: Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"),
            ('{"schemaVersion": 1, "schemaVersion": 1}', "notes.json: duplicate JSON key 'schemaVersion'"),
            ([], "notes.json: catalog root must be an object"),
            ({"entries": entries}, "notes.json: schemaVersion must be 1 or 2"),
            ({"schemaVersion": 3, "entries": entries}, "notes.json: schemaVersion must be 1 or 2"),
            ({"schemaVersion": [], "entries": entries}, "notes.json: schemaVersion must be 1 or 2"),
            ({"schemaVersion": 1, "entries": []}, "notes.json: entries must be an object"),
            ({"schemaVersion": 1, "entries": {"Bad": self.ENTRY}},
             "notes.json: entry 'Bad': id must be a lowercase kebab-case value up to 80 characters"),
            ({"schemaVersion": 1, "entries": {"a" * 81: self.ENTRY}},
             f"notes.json: entry '{'a' * 81}': id must be a lowercase kebab-case value up to 80 characters"),
            ({"schemaVersion": 1, "entries": {"first": {"category": "changed", "message": "x"}}},
             "notes.json: entry 'first': category must be one of new, improved, fixed, removed, internal"),
            (version_two | {"entries": {"Bad": self.ENTRY}, "publicationBaselines": {}},
             "notes.json: entry 'Bad': id must be a lowercase kebab-case value up to 80 characters"),
            (version_two | {"publicationBaselines": []},
             "notes.json: publicationBaselines must contain exactly stable, development, nightly"),
            (version_two | {"publicationBaselines": {"stable": "first"}},
             "notes.json: publicationBaselines must contain exactly stable, development, nightly"),
            (version_two | {"publicationBaselines": self.BASELINES | {"development": "missing"}},
             "notes.json: development publication baseline 'missing' must identify a catalog entry"),
            (version_two | {"publicationBaselines": self.BASELINES | {"stable": 1, "nightly": "missing"}},
             "notes.json: stable publication baseline '1' must identify a catalog entry"),
        )
        for document, message in cases:
            with self.subTest(message=message):
                self.assertEqual(self.refusal(document), message)

    def test_a_catalog_must_hold_exactly_the_fields_of_its_schema(self) -> None:
        cases = (
            ({"schemaVersion": 1, "entries": {}, "publicationBaselines": self.BASELINES}, 1,
             {"schemaVersion", "entries"}),
            ({"schemaVersion": 2, "entries": {}}, 2, {"schemaVersion", "publicationBaselines", "entries"}),
        )
        for document, version, fields in cases:
            with self.subTest(version=version):
                message = self.refusal(document)
                prefix = f"notes.json: schemaVersion {version} catalog must contain only "
                self.assertTrue(message.startswith(prefix), message)
                self.assertEqual(set(message.removeprefix(prefix).split(", ")), fields)

    def test_a_valid_document_keeps_entry_order_and_reads_baselines_by_channel(self) -> None:
        entries = {"second": self.ENTRY, "first": {"category": "new", "message": "Spaces sync."}}
        catalog = release_note_catalog.parse_catalog_document(json.dumps({
            "schemaVersion": 2, "entries": entries,
            "publicationBaselines": {"nightly": "first", "stable": "second", "development": "first"}}), "notes.json")
        self.assertEqual(catalog.schema_version, 2)
        self.assertEqual(list(catalog.publication_baselines.items()),
                         [("stable", "second"), ("development", "first"), ("nightly", "first")])
        self.assertEqual(list(catalog.entries), ["second", "first"])
        self.assertEqual(catalog.entries["first"],
                         release_note_catalog.ReleaseNoteEntry("first", "new", "Spaces sync."))
        legacy = release_note_catalog.parse_catalog_document(
            json.dumps({"schemaVersion": 1, "entries": entries}), "notes.json")
        self.assertEqual((legacy.schema_version, legacy.publication_baselines), (1, {}))


if __name__ == "__main__":
    unittest.main()

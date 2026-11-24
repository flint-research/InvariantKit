import copy
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from invariantkit.documents import DocumentError, canonical_json, load_catalog, read_json, validate
from invariantkit.reporting import build_report

FEE_ID = "erc4626.fee-vault.campaign"
ORACLE_ID = "oracle.chainlink.updated-at"


@pytest.fixture
def definition():
    catalog = load_catalog()
    return next(item for item in catalog["definitions"] if item["id"] == FEE_ID)


@pytest.fixture
def forge_record(definition):
    binding = definition["forge"]
    selectors = {name: {"calls": 1, "reverts": 0, "discards": 0} for name in binding["coverage"]["required_calls"]}
    return {
        "status": "Success",
        "reason": None,
        "kind": {"Invariant": {"runs": 1, "calls": len(selectors), "reverts": 0, "metrics": selectors}},
    }


def _report(definition, record):
    binding = definition["forge"]
    runner = {binding["suite"]: {"test_results": {binding["test"]: record}}}
    return build_report(load_catalog(), runner, [definition["id"]])["results"][0]


def test_pass_report_exposes_observed_counts_and_drops_raw_payload(definition, forge_record):
    forge_record["counterexample"] = {"raw": "raw-data-excluded"}
    forge_record["duration"] = {"secs": 99, "nanos": 0}
    row = _report(definition, forge_record)

    assert row["status"] == "pass"
    assert row["metrics"]["calls"] == 6
    exported = canonical_json(row)
    assert b"successful_actions" not in exported
    assert b"raw-data-excluded" not in exported
    assert b"duration" not in exported


@pytest.mark.parametrize(
    ("status", "reason", "expected", "code"),
    [
        ("Failure", "InsufficientActionCoverage(0x1234, 0)", "inconclusive", "coverage_gate_failed"),
        ("Failure", "UnexpectedFailure(1)", "fail", "forge_failure"),
        ("Failure", "unrelated InsufficientActionCoverage(0x1234, 0)", "fail", "forge_failure"),
        ("Skipped", None, "not_attempted", "test_skipped"),
        ("unknown", None, "error", "invalid_test_result"),
    ],
)
def test_forge_status_and_coverage_are_separate(definition, forge_record, status, reason, expected, code):
    forge_record.update(status=status, reason=reason)
    row = _report(definition, forge_record)
    assert (row["status"], row["reason"]) == (expected, code)


def test_real_zero_assertion_shape_is_inconclusive():
    catalog = load_catalog()
    definition = next(item for item in catalog["definitions"] if item["id"] == "accounting.fee-token.campaign")
    record = {
        "status": "Failure",
        "reason": "no fee-bearing transfers: 0 <= 0",
        "kind": {"Invariant": {"runs": 1, "calls": 1, "reverts": 0}},
    }
    assert _report(definition, record)["reason"] == "coverage_gate_failed"


@pytest.mark.parametrize(
    ("changes", "reason"),
    [
        ({"calls": 0}, "empty_campaign"),
        ({"runs": 0}, "empty_campaign"),
        ({"calls": 6, "reverts": 6}, "all_calls_reverted"),
        ({"metrics": {}}, "required_calls_not_met"),
        ({"calls": False}, "invalid_test_result"),
        ({"calls": -1}, "invalid_test_result"),
        ({"reverts": 7}, "invalid_test_result"),
    ],
)
def test_campaign_evidence(definition, forge_record, changes, reason):
    forge_record["kind"]["Invariant"].update(changes)
    assert _report(definition, forge_record)["reason"] == reason


def test_missing_metrics_are_distinct_from_zero_coverage(definition, forge_record):
    del forge_record["kind"]["Invariant"]["metrics"]
    assert _report(definition, forge_record)["reason"] == "missing_selector_metrics"


def test_missing_setup_failure_and_binding_are_distinct(definition):
    catalog = load_catalog()
    binding = definition["forge"]
    absent = build_report(catalog, {}, [FEE_ID])["results"][0]
    setup = {binding["suite"]: {"test_results": {"setUp()": {"status": "Failure"}}}}
    failed = build_report(catalog, setup, [FEE_ID])["results"][0]
    unbound_definition = copy.deepcopy(definition)
    del unbound_definition["forge"]
    unbound = build_report({"schema_version": "1.0", "definitions": [unbound_definition]}, {}, [FEE_ID])["results"][0]
    assert (absent["status"], absent["reason"]) == ("not_attempted", "test_missing")
    assert (failed["status"], failed["reason"]) == ("error", "setup_failed")
    assert (unbound["status"], unbound["reason"]) == ("not_attempted", "missing_binding")


def test_deterministic_results_ignore_input_order(definition, forge_record):
    catalog = load_catalog()
    binding = definition["forge"]
    suites = {binding["suite"]: {"test_results": {binding["test"]: forge_record}}}
    first = canonical_json(build_report(catalog, suites, [FEE_ID, ORACLE_ID]))
    catalog["definitions"].reverse()
    original = forge_record["kind"]["Invariant"]["metrics"]
    forge_record["kind"]["Invariant"]["metrics"] = dict(reversed(list(original.items())))
    second = canonical_json(build_report(catalog, suites, [ORACLE_ID, FEE_ID]))
    assert first == second


def test_document_validation_rejects_duplicate_ids_and_wrong_version():
    catalog = load_catalog()
    catalog["definitions"].append(catalog["definitions"][0])
    with pytest.raises(DocumentError, match="duplicate definition IDs"):
        validate("definition", catalog)
    catalog["schema_version"] = "2.0"
    with pytest.raises(DocumentError, match="const"):
        validate("definition", catalog)


@pytest.mark.parametrize("content", [b'{"same": 1, "same": 2}', b'{"value": NaN}', b'{"value": 1e400}', b""])
def test_json_parser_rejects_ambiguous_input(tmp_path, content):
    path = tmp_path / "bad.json"
    path.write_bytes(content)
    with pytest.raises(DocumentError):
        read_json(path)


def test_json_size_is_bounded(tmp_path, monkeypatch):
    path = tmp_path / "large.json"
    path.write_bytes(b" " * 17)
    monkeypatch.setattr("invariantkit.documents.MAX_INPUT_BYTES", 16)
    with pytest.raises(DocumentError, match="exceeds"):
        read_json(path)


def test_cli_writes_valid_report_and_uses_exit_status(tmp_path):
    raw = tmp_path / "forge.json"
    raw.write_text("{}", encoding="utf-8")
    root = Path(__file__).resolve().parents[2]
    command = [sys.executable, "-m", "invariantkit", "report", str(raw), "--id", ORACLE_ID]
    environment = os.environ | {"PYTHONPATH": str(root / "cli")}
    result = subprocess.run(command, env=environment, capture_output=True, check=False)
    assert result.returncode == 1
    report = json.loads(result.stdout)
    validate("result", report)
    assert report["results"][0]["status"] == "not_attempted"

    raw.write_text('{"junk": {}}', encoding="utf-8")
    invalid = subprocess.run(command, env=environment, capture_output=True, check=False)
    assert invalid.returncode == 2
    assert invalid.stdout == b""


def test_pass_report_requires_observed_result(definition, forge_record):
    binding = definition["forge"]
    suite = {binding["suite"]: {"test_results": {binding["test"]: forge_record}}}
    report = build_report(load_catalog(), suite, [FEE_ID])
    del report["results"][0]["forge_status"]
    with pytest.raises(DocumentError, match="required"):
        validate("result", report)

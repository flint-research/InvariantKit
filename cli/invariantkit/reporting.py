from . import __version__
from .documents import DocumentError, validate

FORGE_KINDS = {"unit": "Unit", "fuzz": "Fuzz", "invariant": "Invariant"}
FORGE_STATUSES = {"Success", "Failure", "Skipped"}
MAX_COUNT = (1 << 64) - 1


def _count(record, field: str) -> int:
    value = record.get(field)
    if type(value) is not int or not 0 <= value <= MAX_COUNT:
        raise DocumentError("invalid counter in Forge result")
    return value


def _metrics(kind: str, actual):
    expected = FORGE_KINDS[kind]
    if not isinstance(actual, dict) or len(actual) != 1 or not isinstance(actual.get(expected), dict):
        raise DocumentError("unexpected Forge test kind")

    values = actual[expected]
    if kind == "unit":
        return None

    metrics = {"runs": _count(values, "runs")}
    if kind == "fuzz":
        return metrics

    metrics["calls"] = _count(values, "calls")
    metrics["reverts"] = _count(values, "reverts")
    if metrics["reverts"] > metrics["calls"]:
        raise DocumentError("Forge reports more reverts than calls")

    if "metrics" in values:
        selectors = values["metrics"]
        if not isinstance(selectors, dict) or len(selectors) > 4096:
            raise DocumentError("invalid Forge selector metrics")

        metrics["selectors"] = []
        for name, counts in sorted(selectors.items()):
            if not 0 < len(name) <= 512 or not name.isprintable() or not isinstance(counts, dict):
                raise DocumentError("invalid Forge selector metric")
            row = {"name": name, **{field: _count(counts, field) for field in ("calls", "reverts", "discards")}}
            if row["reverts"] > row["calls"]:
                raise DocumentError("Forge reports more selector reverts than calls")
            metrics["selectors"].append(row)

    return metrics


def _coverage_gate_failed(reason, coverage) -> bool:
    if not isinstance(reason, str) or len(reason) > 512:
        return False
    name, argument_list, _ = reason.partition("(")
    if argument_list and reason.endswith(")") and name in coverage.get("custom_errors", []):
        return True
    return any(reason == f"{message}: 0 <= 0" for message in coverage.get("zero_assertions", []))


def _classify(status: str, reason, coverage, metrics):
    if status == "Failure":
        if _coverage_gate_failed(reason, coverage):
            return "inconclusive", "coverage_gate_failed"
        return "fail", "forge_failure"

    if metrics is not None and (metrics["runs"] == 0 or metrics.get("calls") == 0):
        return "inconclusive", "empty_campaign"
    if metrics is not None and "calls" in metrics and metrics["calls"] == metrics["reverts"]:
        return "inconclusive", "all_calls_reverted"

    requirements = coverage.get("required_calls", {})
    if requirements:
        if metrics is None or "selectors" not in metrics:
            return "inconclusive", "missing_selector_metrics"
        calls = {entry["name"]: entry["calls"] for entry in metrics["selectors"]}
        if any(calls.get(name, 0) < minimum for name, minimum in requirements.items()):
            return "inconclusive", "required_calls_not_met"
    return "pass", None


def _outcome(row, status: str, reason: str | None):
    return {**row, "status": status, "reason": reason}


def _row(definition, suites):
    row = {"id": definition["id"]}
    binding = definition.get("forge")
    if binding is None:
        return _outcome(row, "not_attempted", "missing_binding")

    row["test"] = {field: binding[field] for field in ("suite", "test", "kind")}
    results = suites.get(binding["suite"], {})
    if binding["test"] not in results:
        setup = results.get("setUp()")
        if isinstance(setup, dict) and setup.get("status") == "Failure":
            return _outcome(row, "error", "setup_failed")
        return _outcome(row, "not_attempted", "test_missing")

    result = results[binding["test"]]
    status = result.get("status") if isinstance(result, dict) else None
    if not isinstance(status, str) or status not in FORGE_STATUSES:
        return _outcome(row, "error", "invalid_test_result")

    row["forge_status"] = status
    if status == "Skipped":
        return _outcome(row, "not_attempted", "test_skipped")

    try:
        metrics = _metrics(binding["kind"], result.get("kind"))
    except DocumentError:
        return _outcome(row, "error", "invalid_test_result")

    if metrics is not None:
        row["metrics"] = metrics
    outcome, reason = _classify(status, result.get("reason"), binding.get("coverage", {}), metrics)
    return _outcome(row, outcome, reason)


def build_report(catalog, forge_result, identifiers=()):
    validate("definition", catalog)
    if not isinstance(forge_result, dict):
        raise DocumentError("expected a Forge JSON object keyed by test suite")

    suites = {}
    for name, suite in forge_result.items():
        if not isinstance(suite, dict) or not isinstance(suite.get("test_results"), dict):
            raise DocumentError("expected a Forge suite with a test_results object")
        suites[name] = suite["test_results"]

    definitions = {item["id"]: item for item in catalog["definitions"]}
    selected = set(identifiers) or definitions.keys()
    unknown = selected - definitions.keys()
    if unknown:
        raise DocumentError(f"unknown property ID {min(unknown)!r}")

    report = {
        "schema_version": "1.0",
        "tool": {"name": "invariantkit", "version": __version__},
        "runner": "forge",
        "results": [_row(definitions[identifier], suites) for identifier in sorted(selected)],
    }
    validate("result", report)
    return report

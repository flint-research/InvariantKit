import json
import math
from functools import cache
from importlib.resources import files
from pathlib import Path

from jsonschema import Draft202012Validator

MAX_INPUT_BYTES = 64 * 1024 * 1024


class DocumentError(ValueError):
    pass


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DocumentError("duplicate JSON object key")
        result[key] = value
    return result


def _finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise DocumentError("JSON numbers must be finite")
    return number


def _reject_constant(_value):
    raise DocumentError("JSON numbers must be finite")


def read_json(path: Path):
    if not path.is_file():
        raise DocumentError("expected a readable JSON file")
    with path.open("rb") as source:
        data = source.read(MAX_INPUT_BYTES + 1)
    if len(data) > MAX_INPUT_BYTES:
        raise DocumentError("JSON input exceeds 64 MiB")

    try:
        return json.loads(
            data, object_pairs_hook=_unique_object, parse_float=_finite_float, parse_constant=_reject_constant
        )
    except json.JSONDecodeError as error:
        raise DocumentError(f"invalid JSON at line {error.lineno}, column {error.colno}") from error
    except DocumentError:
        raise
    except (ValueError, RecursionError) as error:
        raise DocumentError("JSON encoding or nesting is unsupported") from error


def _resource(folder: str, filename: str):
    resource = files("invariantkit").joinpath(folder).joinpath(filename)
    return json.loads(resource.read_text(encoding="utf-8"))


@cache
def _validator(kind: str):
    schema = _resource("schemas", f"{kind}.schema.json")
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validate(kind: str, data) -> None:
    error = next(_validator(kind).iter_errors(data), None)
    if error is not None:
        path = ascii(list(error.absolute_path))[:160]
        raise DocumentError(f"invalid {kind} at {path} ({error.validator})")

    entries = data["definitions" if kind == "definition" else "results"]
    ids = {entry["id"] for entry in entries}
    if len(ids) != len(entries):
        raise DocumentError(f"duplicate {kind} IDs")


def load_catalog(path: Path | None = None):
    data = _resource("data", "catalog.json") if path is None else read_json(path)
    validate("definition", data)
    return data


def canonical_json(data) -> bytes:
    return (json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")

import argparse
import sys
from pathlib import Path

from . import __version__
from .documents import DocumentError, canonical_json, load_catalog, read_json, validate
from .reporting import build_report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="invariantkit")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="Print the property catalog as JSON")
    listing.add_argument("--definitions", type=Path)

    validation = commands.add_parser("validate", help="Validate a definition catalog or report")
    validation.add_argument("kind", choices=("definition", "result"))
    validation.add_argument("file", type=Path)

    reporting = commands.add_parser("report", help="Convert a saved Forge JSON result to an InvariantKit report")
    reporting.add_argument("forge_json", type=Path)
    reporting.add_argument("--definitions", type=Path)
    reporting.add_argument("--id", action="append", default=[], help="Select a property ID. Repeat to select more.")

    args = parser.parse_args(argv)
    try:
        if args.command == "validate":
            validate(args.kind, read_json(args.file))
            return 0

        catalog = load_catalog(args.definitions)
        if args.command == "list":
            catalog["definitions"].sort(key=lambda entry: entry["id"])
            sys.stdout.buffer.write(canonical_json(catalog))
            return 0

        report = build_report(catalog, read_json(args.forge_json), args.id)
        sys.stdout.buffer.write(canonical_json(report))
        return int(any(result["status"] != "pass" for result in report["results"]))
    except (DocumentError, OSError) as error:
        print(f"invariantkit: {error}", file=sys.stderr)
        return 2

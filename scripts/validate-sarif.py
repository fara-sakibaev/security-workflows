#!/usr/bin/env python3
import json
import pathlib
import sys


def validate(path: pathlib.Path) -> None:
    if not path.is_file():
        raise ValueError(f"SARIF file does not exist: {path}")
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict) or data.get("version") != "2.1.0":
        raise ValueError(f"invalid SARIF version in {path}")
    runs = data.get("runs")
    if not isinstance(runs, list):
        raise ValueError(f"SARIF runs must be an array in {path}")
    for index, run in enumerate(runs):
        if not isinstance(run, dict):
            raise ValueError(f"SARIF run {index} is not an object in {path}")
        driver = run.get("tool", {}).get("driver", {})
        if not isinstance(driver, dict) or not isinstance(driver.get("name"), str):
            raise ValueError(f"SARIF run {index} has no tool.driver.name in {path}")
        if "results" in run and not isinstance(run["results"], list):
            raise ValueError(f"SARIF run {index} results are not an array in {path}")


if len(sys.argv) < 2:
    raise SystemExit("usage: validate-sarif.py FILE [FILE ...]")
for argument in sys.argv[1:]:
    try:
        validate(pathlib.Path(argument))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(str(error)) from error

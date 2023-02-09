#!/usr/bin/env python3

from os.path import isfile
import xmltodict
import json
import subprocess
import tempfile
import argparse
import os
import pathlib

from dataclasses import dataclass, asdict
import typing as t

status_t = t.Literal["pass", "fail", "error"]


@dataclass
class Test:
    name: str
    status: status_t
    message: t.Optional[str]
    output: t.Optional[str]
    test_code: t.Optional[str]


@dataclass
class Result:
    version: int
    status: status_t
    message: t.Optional[str]
    tests: t.Optional[t.List[Test]]

    def to_dict(self):
        return asdict(self)

    def to_json(self):
        return json.dumps(self.to_dict())


class ProcessJUnit:
    data: t.Dict[str, t.Any]

    def __init__(self, file_name: str):
        with open(file_name, "r") as f:
            data = xmltodict.parse(f.read(), process_namespaces=True)
            self.data = data["testsuites"]["testsuite"]

    @property
    def status(self) -> status_t:
        if int(self.data.get("@errors", 0)) > 0:
            return "error"
        if int(self.data.get("@failures", 0)) > 0:
            return "fail"
        return "pass"

    @property
    def tests(self) -> t.List[Test]:
        r = []
        for test in self.data.get("testcase", []):
            r.append(
                Test(
                    name=test.get("@name"),
                    status="fail" if "failure" in test else "pass",
                    message=test.get("failure", {}).get("#text", None),
                    output=None,
                    test_code=None,
                )
            )
        return r

    @property
    def result(self) -> Result:
        return Result(version=2, status=self.status, message=None, tests=self.tests)


def run_test(path) -> Result:
    # TODO: We don't currently clean up these temp directories, but since they
    # execute in containers, there is a low risk of them exploding the file system.
    tmpdir = tempfile.TemporaryDirectory()
    junit_file = os.path.join(tmpdir.name, "junit.xml")
    os.environ["OUNIT_OUTPUT_JUNIT_FILE"] = junit_file

    try:
        # We discard the output on success since we now rely on the junit output.
        # The output is still caught on error and captured by the exception.
        subprocess.check_output(
            ["make", "-C", path],
            text=True,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        if not os.path.isfile(junit_file):
            return Result(version=2, status="error", message=e.output, tests=None)

    return ProcessJUnit(junit_file).result


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="Excerism Ocaml Test Runner",
        description="Run the test runner on a solution.",
    )

    parser.add_argument("slug", type=str, help="exercise slug")
    parser.add_argument(
        "input_dir", type=pathlib.Path, help="absolute path to solution folder"
    )
    parser.add_argument(
        "output_dir", type=pathlib.Path, help="absolute path to output directory"
    )

    args = parser.parse_args()

    exercise = args.slug.replace("-", "_")
    results_file = os.path.join(args.output_dir, "results.json")

    # TODO: implementation_file and tests_file are cargo culted from the previous
    # bash version. They are unused, but kept around in case there was plans.
    implementation_file = os.path.join(args.input_dir, f"{exercise}.pl")
    tests_file = os.path.join(args.input_dir, f"{exercise}_tests.plt")

    os.makedirs(args.output_dir, exist_ok=True)

    with open(results_file, "w+") as f:
        f.write(run_test(args.input_dir).to_json())


if __name__ == "__main__":
    main()

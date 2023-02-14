#!/usr/bin/env python3

from os.path import isfile
import xmltodict
import json
import subprocess
import tempfile
import argparse
import os
import pathlib
import re

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
        return json.dumps(self.to_dict(), indent=2)


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

    @staticmethod
    def _testcase_to_test(test: t.Dict[str, t.Any]) -> Test:
        return Test(
            name=test.get("@name"),
            status="fail" if "failure" in test else "pass",
            message=test.get("failure", {}).get("#text", None),
            output=None,
            test_code=None,
        )

    @property
    def tests(self) -> t.List[Test]:
        r = []
        testcases = self.data.get("testcase", [])
        if not isinstance(testcases, list):
            return [self._testcase_to_test(testcases)]
        for test in testcases:
            r.append(self._testcase_to_test(test))
        return r

    @property
    def result(self) -> Result:
        return Result(version=2, status=self.status, message=None, tests=self.tests)


def sanitize_output(output: str) -> str:

    # Remove make outputs
    output = re.sub(
        r"("
        + r"make: (Entering|Leaving) directory '[^']+'"
        + r"|dune (clean|runtest)"
        + r")"
        + r"| *test alias runtest \(exit 1\)"
        + r"|\(cd _build[^\)]+\)",
        "",
        output,
    )

    # Remove variable test numbering
    output = re.sub(r"tests-[^\.]+\.log", "tests.log", output)

    # Remove variable elapsed time
    output = re.sub(r"in: [0-9]+\.[0-9]+ seconds\.", "", output)

    # Remove blank lines
    output = "\n".join([ll.rstrip() for ll in output.splitlines() if ll.strip()])

    return output


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
            return Result(
                version=2, status="error", message=sanitize_output(e.output), tests=None
            )

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

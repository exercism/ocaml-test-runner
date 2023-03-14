#!/usr/bin/env bash

TOP=$(dirname $( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd ))

cd "$TOP"

exec ./bin/runner "${@}"

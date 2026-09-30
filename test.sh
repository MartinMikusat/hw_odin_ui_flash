#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$ROOT/build"
hw-odin test "$ROOT" -out:"$ROOT/build/tests" -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true "$@"

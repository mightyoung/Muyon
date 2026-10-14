#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec node --test flow.test.mjs server.test.mjs process.test.mjs

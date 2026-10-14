#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 FILE SCHEMA" >&2
  exit 2
fi

readonly source_commit=2166123eb256fa40baef7e22ab1379708425efc7
readonly bundle_sha256=c943a9ab579e35de231cd1f3278d8ab1be178470eed636bb4bbe65cb083b762d
readonly archive_sha256=270a90bc9e223637b8ecdd22b86a5be157732245ae37f5f2416edf9336b65c04
readonly validator_url="https://codeload.github.com/cardinalby/schema-validator-action/tar.gz/${source_commit}"
readonly cache_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
readonly source_dir="${cache_dir}/cardinalby-schema-validator-${source_commit}"
readonly validator="${source_dir}/dist/index.js"

verify_sha256() {
  node - "$1" "$2" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");

const [path, expected] = process.argv.slice(2);
const actual = crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex");
if (actual !== expected) {
  console.error(`schema validator bundle SHA-256 mismatch: ${actual}`);
  process.exit(1);
}
NODE
}

if [[ ! -f "$validator" ]]; then
  if [[ -e "$source_dir" ]]; then
    echo "incomplete schema validator source already exists: $source_dir" >&2
    exit 1
  fi

  temporary_archive="$(mktemp "${cache_dir}/cardinalby-schema-validator.XXXXXX")"
  temporary_source="$(mktemp -d "${cache_dir}/cardinalby-schema-source.XXXXXX")"
  trap 'rm -f "$temporary_archive"; rm -rf "$temporary_source"' EXIT
  curl --fail --silent --show-error --location "$validator_url" --output "$temporary_archive"
  verify_sha256 "$temporary_archive" "$archive_sha256"
  tar --extract --gzip --file "$temporary_archive" --strip-components=1 --directory "$temporary_source"
  if [[ ! -f "$temporary_source/dist/index.js" || ! -f "$temporary_source/metaSchemas/schema-files.json" ]]; then
    echo "schema validator source archive is missing runtime files" >&2
    exit 1
  fi
  verify_sha256 "$temporary_source/dist/index.js" "$bundle_sha256"
  mv "$temporary_source" "$source_dir"
  trap 'rm -f "$temporary_archive"' EXIT
fi

verify_sha256 "$validator" "$bundle_sha256"

INPUT_FILE="$1" \
INPUT_SCHEMA="$2" \
INPUT_FILEPARSER=auto \
INPUT_MODE=default \
INPUT_FIXSCHEMAS=false \
  node "$validator"

#!/usr/bin/env bash
set -euo pipefail

# scripts/crea_scheme.sh
# Create a SQLite database and a dns_records table with the exact column names
# used in etc/records.tsv: name, type, value, priority
# Usage:
#   ./scripts/crea_scheme.sh                     # creates etc/dns_records.db
#   ./scripts/crea_scheme.sh DB_PATH             # creates DB at DB_PATH
#   ./scripts/crea_scheme.sh DB_PATH import TSV  # creates DB then imports TSV (skips header)
#   ./scripts/crea_scheme.sh DB_PATH export OUT  # exports dns_records table to OUT TSV (with header)
# Examples:
#   ./scripts/crea_scheme.sh
#   ./scripts/crea_scheme.sh /tmp/dns.db import etc/records.tsv
#   ./scripts/crea_scheme.sh /tmp/dns.db export /tmp/out.tsv

DB_PATH_DEFAULT="etc/dns_records.db"
DB="${1:-$DB_PATH_DEFAULT}"
CMD="${2:-create}"
FILE_ARG="${3:-}"

usage() {
  cat <<USAGE
Usage:
  $0 [DB_PATH] [create]
  $0 [DB_PATH] import <TSV_FILE>
  $0 [DB_PATH] export <OUT_TSV>

If DB_PATH is omitted it defaults to: $DB_PATH_DEFAULT
'import' will load a TSV file (skipping header) into dns_records.
'export' will dump the dns_records table to a TSV file (including a header).
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
  usage
  exit 0
fi

mkdir -p "$(dirname "$DB")"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "ERROR: sqlite3 CLI is required but not found in PATH."
  exit 1
fi

create_schema() {
  cat > /tmp/crea_scheme_sql.$$ <<'SQL'
BEGIN;

-- Create table with exact column names from the TSV header
CREATE TABLE IF NOT EXISTS dns_records (
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  priority INTEGER
);

-- Helpful index for lookups by name+type
CREATE INDEX IF NOT EXISTS idx_dns_records_name_type ON dns_records(name, type);

COMMIT;
SQL

  echo "Creating/ensuring SQLite DB and schema at: $DB"
  sqlite3 "$DB" ".read /tmp/crea_scheme_sql.$$"
  rm -f /tmp/crea_scheme_sql.$$
}

import_tsv() {
  local tsv="$1"
  if [ ! -f "$tsv" ]; then
    echo "ERROR: TSV file '$tsv' not found."
    exit 1
  fi

  echo "Importing TSV records from $tsv into dns_records (skipping header)..."
  TMP_TSV=$(mktemp)
  tail -n +2 "$tsv" > "$TMP_TSV"

  # Ensure table exists before import
  create_schema

  # Use sqlite3's .mode and .import to load tab-separated values
  sqlite3 "$DB" <<-SQLCMD
    .mode tabs
    .import $TMP_TSV dns_records
  SQLCMD

  rm -f "$TMP_TSV"
  echo "Import complete."
}

export_tsv() {
  local out="$1"
  echo "Exporting dns_records to $out (header + tab-separated rows)..."

  # Ensure DB exists
  if [ ! -f "$DB" ]; then
    echo "ERROR: DB file '$DB' does not exist. Create it first or run import."
    exit 1
  fi

  # Write header then data using sqlite3 with tab separator
  {
    printf 'name\ttype\tvalue\tpriority\n'
    sqlite3 -separator $'\t' "$DB" "SELECT name, type, value, COALESCE(priority, 0) FROM dns_records;"
  } > "$out"

  echo "Export complete. Output: $out"
}

case "$CMD" in
  create)
    create_schema
    ;;
  import)
    if [ -z "$FILE_ARG" ]; then
      echo "ERROR: import requires a TSV file argument."
      usage
      exit 1
    fi
    import_tsv "$FILE_ARG"
    ;;
  export)
    if [ -z "$FILE_ARG" ]; then
      echo "ERROR: export requires an output TSV file argument."
      usage
      exit 1
    fi
    export_tsv "$FILE_ARG"
    ;;
  *)
    echo "Unknown command: $CMD"
    usage
    exit 2
    ;;
esac

echo "Done. Database: $DB"

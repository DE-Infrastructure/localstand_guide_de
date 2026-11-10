#!/usr/bin/env bash
# Read SQL from stdin using the PostgreSQL client already bundled with Greenplum.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose exec -T greenplum bash -c \
  'source /usr/local/greenplum-db/greenplum_path.sh; PGPASSWORD="$GREENPLUM_PASSWORD" exec psql -h greenplum -U gpadmin -d dwh -v ON_ERROR_STOP=1 "$@"' -- "$@"

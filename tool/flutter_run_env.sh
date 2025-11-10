#!/usr/bin/env bash
set -euo pipefail

# Injecte SUPABASE_URL et SUPABASE_ANON_KEY via --dart-define pour flutter run.
if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "❌ SUPABASE_URL et SUPABASE_ANON_KEY doivent être définies dans l'environnement." >&2
  exit 1
fi

flutter run "$@" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

# .github/scripts/detect-changed-modules.sh
#!/usr/bin/env bash
# Outputs a JSON array of changed modules for use as a GitHub Actions matrix.
# Usage: detect-changed-modules.sh <base_ref> <head_ref>
#
# Edge cases handled:
#   - Shared files changed (root *.tf, *.hcl, .github/) → all modules
#   - Workflow files changed                             → all modules
#   - No module files changed                            → empty array []

set -euo pipefail

BASE_REF="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"
ALL_MODULES='["vpc","eks","kubernetes-addons","cicd-state"]'

CHANGED=$(git diff --name-only "${BASE_REF}...${HEAD_REF}")

# Trigger all modules if shared/root-level infra files changed
if echo "$CHANGED" | grep -qE '^(\.github/|terragrunt\.hcl$|\.terraform-version$|modules/)'; then
  echo "$ALL_MODULES"
  exit 0
fi

# Build array of affected modules from changed paths
MODULES=()
for MODULE in vpc eks kubernetes-addons cicd-state; do
  if echo "$CHANGED" | grep -q "^${MODULE}/"; then
    MODULES+=("\"${MODULE}\"")
  fi
done

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "[]"
else
  echo "[$(IFS=,; echo "${MODULES[*]}")]"
fi
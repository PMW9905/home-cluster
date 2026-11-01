#!/usr/bin/env bash
# Refresh your talosconfig and kubeconfig from topf and merge them into your
# default client configs, replacing the previous entry for this cluster.
#
# Usage:  ./refresh-configs.sh
#
# Optional environment overrides:
#   TOPF_DIR    directory containing topf.yaml (default: this script's directory)
#   TALOSCONFIG talosconfig to update           (default: ~/.talos/config)
#   KUBECONFIG  kubeconfig to update            (default: ~/.kube/config; first entry if a list)
#   VALIDITY    passed to `topf kubeconfig --validity` (topf's default is 12h)
#
# topf decrypts secrets.yaml with SOPS, so SOPS_AGE_KEY_FILE must be set (or your
# age key must be in a location SOPS checks) in the shell you run this from.
set -euo pipefail
umask 077

cd "${TOPF_DIR:-$(dirname "$0")}"

for bin in topf talosctl kubectl; do
  command -v "$bin" >/dev/null || { echo "error: '$bin' not found in PATH" >&2; exit 1; }
done

talos_path="${TALOSCONFIG:-$HOME/.talos/config}"
kube_path="${KUBECONFIG:-$HOME/.kube/config}"
kube_path="${kube_path%%:*}"   # if KUBECONFIG is a list, update the first file

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- generate fresh configs (both commands print to stdout) -------------------
echo "Generating configs with topf ..."
topf talosconfig > "$tmp/talosconfig"
validity_args=()
[[ -n "${VALIDITY:-}" ]] && validity_args=(--validity "$VALIDITY")
topf kubeconfig ${validity_args[@]+"${validity_args[@]}"} > "$tmp/kubeconfig"

[[ -s "$tmp/talosconfig" ]] || { echo "error: topf produced an empty talosconfig" >&2; exit 1; }
[[ -s "$tmp/kubeconfig"  ]] || { echo "error: topf produced an empty kubeconfig"  >&2; exit 1; }

# --- talosconfig ---------------------------------------------------------------
ctx="$(awk '/^context:/ {print $2; exit}' "$tmp/talosconfig")"
[[ -n "$ctx" ]] || { echo "error: could not read the context name from the generated talosconfig" >&2; exit 1; }

mkdir -p "$(dirname "$talos_path")"
if [[ -f "$talos_path" ]]; then
  cp "$talos_path" "$talos_path.bak"
  if ! talosctl --talosconfig "$talos_path" config contexts >/dev/null 2>&1; then
    echo "warning: $talos_path is unreadable (backup at $talos_path.bak); replacing it"
    rm -f "$talos_path"
  else
    # Drop the old copy of this context first, or merge would keep it and add a
    # renamed duplicate (e.g. "<name>-1"). talosctl refuses to remove the current
    # context, so switch to another one first; if this is the only context, just
    # start from a fresh file.
    contexts="$(talosctl --talosconfig "$talos_path" config contexts | awk 'NR>1 {print ($1=="*") ? $2 : $1}')"
    if grep -qxF "$ctx" <<<"$contexts"; then
      other="$(grep -vxF "$ctx" <<<"$contexts" | head -n 1 || true)"
      if [[ -n "$other" ]]; then
        talosctl --talosconfig "$talos_path" config context "$other" >/dev/null
        talosctl --talosconfig "$talos_path" config remove "$ctx" --noconfirm >/dev/null
      else
        rm -f "$talos_path"
      fi
    fi
  fi
fi
talosctl --talosconfig "$talos_path" config merge "$tmp/talosconfig"
talosctl --talosconfig "$talos_path" config context "$ctx" >/dev/null
echo "Updated talosconfig: $talos_path (context: $ctx)"

# --- kubeconfig ----------------------------------------------------------------
# kubectl takes the FIRST file's value when names clash, so listing the new file
# first makes the fresh credentials win over the old entry.
mkdir -p "$(dirname "$kube_path")"
if [[ -f "$kube_path" ]]; then
  cp "$kube_path" "$kube_path.bak"
  KUBECONFIG="$tmp/kubeconfig:$kube_path" kubectl config view --flatten > "$tmp/merged"
else
  cp "$tmp/kubeconfig" "$tmp/merged"
fi
install -m 600 "$tmp/merged" "$kube_path"
echo "Updated kubeconfig:  $kube_path"

# --- quick check (non-fatal) ---------------------------------------------------
echo
KUBECONFIG="$kube_path" kubectl --request-timeout=10s get nodes || \
  echo "note: kubectl check failed; the cluster may be unreachable or still starting"

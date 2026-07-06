#!/usr/bin/env bash
# Fetch Triton model weights into ./model_repository. Weights are gitignored (large
# binaries); this restores them on any host. config.pbtxt files are committed.
#   SCRFD-10G + ArcFace R50  → public InsightFace buffalo_l (auto-download)
#   FairFace / antispoofing  → copy from a local dir via MODEL_SRC_DIR (internal weights)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/model_repository"
SRC_DIR="${MODEL_SRC_DIR:-}"

need() { [ -f "$1" ] && { echo "  ✓ $(basename "$1") present"; return 1; } || return 0; }

# --- SCRFD + ArcFace from buffalo_l (public) ---
if need "$REPO/scrfd_10g/1/model.onnx" || need "$REPO/arcface_r50/1/model.onnx"; then
  tmp=$(mktemp -d); echo "  ↓ buffalo_l.zip"
  curl -fSL https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip -o "$tmp/b.zip"
  python3 - "$tmp/b.zip" "$REPO" <<'PY'
import sys, zipfile
from pathlib import Path
zf, repo = zipfile.ZipFile(sys.argv[1]), Path(sys.argv[2])
m = {"det_10g.onnx": repo/"scrfd_10g/1/model.onnx", "w600k_r50.onnx": repo/"arcface_r50/1/model.onnx"}
for n in zf.namelist():
    b = Path(n).name
    if b in m: m[b].parent.mkdir(parents=True, exist_ok=True); m[b].write_bytes(zf.read(n)); print(f"    -> {m[b]}")
PY
  rm -rf "$tmp"
fi

# --- FairFace + antispoofing from internal store (MODEL_SRC_DIR) ---
for pair in "fairface.onnx:fairface/1/model.onnx" "antispoofing.onnx:antispoofing/1/model.onnx"; do
  src="${pair%%:*}"; dst="$REPO/${pair##*:}"
  [ -f "$dst" ] && { echo "  ✓ ${pair##*:} present"; continue; }
  if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$src" ]; then
    mkdir -p "$(dirname "$dst")"; cp "$SRC_DIR/$src" "$dst"; echo "    -> $dst (from $SRC_DIR)"
  else
    echo "  - $src not found (optional; set MODEL_SRC_DIR to the internal weights dir)"
  fi
done
echo "done. Reload Triton:  docker compose up -d triton"

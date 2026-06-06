#!/usr/bin/env bash
#
# setup.sh — my local uv-based adaptation of ARENA/install.sh
#
# This is MINE, not the vendored ARENA installer. It targets my actual setup:
# Windows + Git Bash + VS Code, with Python/envs managed by uv (no conda, no
# RunPod/Vast.ai, no apt). It creates a project .venv from uv's managed 3.11,
# installs the ARENA deps into it, sanity-checks the GPU, and writes VS Code
# workspace settings. Safe to re-run (idempotent).
#
# Usage (from Git Bash):
#   bash setup.sh                  # venv + deps + GPU check + VS Code settings
#   bash setup.sh --llm-context    # ALSO clone callummcdougall/arena-llm-context
#
set -euo pipefail

# Always operate from the repo root (this script's own directory), so every
# path below is relative and nothing is tied to a username or machine.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Options ---
CLONE_LLM_CONTEXT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --llm-context) CLONE_LLM_CONTEXT=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

REQUIREMENTS="ARENA/requirements.txt"

# --- 0. Require uv on PATH ---
echo "=== Checking for uv ==="
if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: 'uv' is not on your PATH." >&2
    echo "Install it from https://docs.astral.sh/uv/ and re-run this script." >&2
    exit 1
fi
echo "Found uv: $(uv --version)"

# --- 1. Create the project venv (uv supplies managed Python 3.11) ---
if [[ -d .venv ]]; then
    echo "=== .venv already exists — skipping creation ==="
else
    echo "=== Creating .venv with uv (Python 3.11) ==="
    uv venv --python 3.11
fi

# --- 2. Install dependencies into .venv (uv targets it automatically) ---
echo "=== Installing ARENA requirements from $REQUIREMENTS ==="
uv pip install -r "$REQUIREMENTS"

echo "=== Installing ipykernel (for VS Code / Jupyter) ==="
uv pip install ipykernel

# --- 3. Verify the GPU is usable (RTX 5080 / Blackwell needs a cu128+ torch) ---
echo "=== Verifying torch + CUDA ==="
GPU_OK=true
GPU_REPORT="$(uv run python -c 'import torch; print(torch.__version__, torch.cuda.is_available())' 2>&1)" || GPU_OK=false
echo "torch: $GPU_REPORT"

if [[ "$GPU_OK" != true || "$GPU_REPORT" != *True* ]]; then
    echo ""
    echo "WARNING: torch could not use the GPU (got: $GPU_REPORT)." >&2
    echo "This machine has an NVIDIA RTX 5080 (Blackwell), which needs a CUDA 12.8+" >&2
    echo "torch build. The pinned requirements use an older CUDA wheel. NOT auto-" >&2
    echo "reinstalling — install a cu128 build yourself, e.g.:" >&2
    echo "" >&2
    echo "  uv pip install --reinstall torch torchvision \\" >&2
    echo "    --index-url https://download.pytorch.org/whl/cu128" >&2
    echo ""
fi

# --- 4. Optional: clone the arena-llm-context helper repo (off by default) ---
if [[ "$CLONE_LLM_CONTEXT" == true ]]; then
    if [[ -d arena-llm-context ]]; then
        echo "=== arena-llm-context already cloned — skipping ==="
    else
        echo "=== Cloning callummcdougall/arena-llm-context ==="
        git clone -b main https://github.com/callummcdougall/arena-llm-context.git
    fi
fi

# --- 5. Write / merge VS Code workspace settings ---
echo "=== Writing .vscode/settings.json ==="
mkdir -p .vscode
uv run python - <<'PY'
import json, os

settings_path = os.path.join(".vscode", "settings.json")

chapters = [
    "chapter0_fundamentals",
    "chapter1_transformer_interp",
    "chapter2_rl",
    "chapter3_llm_evals",
    "chapter4_alignment_science",
]
extra_paths = [f"ARENA/{c}/exercises" for c in chapters]
interp = "${workspaceFolder}/.venv/Scripts/python.exe"

# Merge into existing settings rather than overwriting.
data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"  (could not parse existing settings.json: {e}; recreating)")
        data = {}

data["python.defaultInterpreterPath"] = interp

# Union extraPaths, preserving any the user already had.
existing = data.get("python.analysis.extraPaths", [])
if not isinstance(existing, list):
    existing = []
merged = list(existing)
for p in extra_paths:
    if p not in merged:
        merged.append(p)
data["python.analysis.extraPaths"] = merged

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")

print(f"  wrote {settings_path}")
PY

echo "=== Done! ==="

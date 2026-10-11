#!/usr/bin/env bash
# Every Translation.tr("...") literal in the shell has a key in translations/en_US.json.
# A missing key shows English at run time, so nothing else notices the drift; the
# 2026-10 pass found 1038 keys missing. The literals come from the translation
# tool's own extractor, so the test and `manage-translations.sh update` agree.
#
# Hooks for exercising the test itself:
#   TRANSLATION_SRC=<dir>   source tree to scan (default: the shell)
#   TRANSLATION_EN=<file>   the en_US.json to check against
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/dots/.config/quickshell/koompi"
TOOL="$SHELL_DIR/translations/tools/translation-manager.py"
SRC="${TRANSLATION_SRC:-$SHELL_DIR}"
EN="${TRANSLATION_EN:-$SHELL_DIR/translations/en_US.json}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "skipping: python3 not installed"
    exit 0
fi

missing="$(python3 -I - "$TOOL" "$SRC" "$EN" <<'PY'
import importlib.util, json, sys, tempfile
tool, src, en = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("translation_manager", tool)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
with tempfile.TemporaryDirectory() as tmp:
    texts = mod.TranslationManager(tmp, src).extract_translatable_texts()
keys = set(json.load(open(en, encoding="utf-8")))
for text in sorted(texts - keys):
    print(json.dumps(text, ensure_ascii=False))
PY
)" || { echo "FAIL: the extractor did not run" >&2; exit 1; }

if [[ -n "$missing" ]]; then
    count="$(wc -l <<<"$missing")"
    echo "FAIL: $count Translation.tr literal(s) have no key in en_US.json:" >&2
    head -20 <<<"$missing" >&2
    echo "run: dots/.config/quickshell/koompi/translations/tools/manage-translations.sh update (see docs/agents/translations.md)" >&2
    exit 1
fi
echo "ok: every Translation.tr literal has an en_US.json key"

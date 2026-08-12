#!/usr/bin/env bash
# =============================================================================
# spatial profile self-check
# =============================================================================
# Proves the container can do what the profile claims. Deliberately NOT `set -e`:
# every probe runs so the table is complete, and the exit code carries the
# verdict.
set -uo pipefail

fail=0
ok()  { printf '  OK    %-14s %s\n' "$1" "${2:-}"; }
bad() { printf '  FAIL  %-14s %s\n' "$1" "${2:-}"; fail=1; }

export PATH="$HOME/.local/bin:$PATH"
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)" 2>/dev/null || true
fi

# Overridable so the gate can point the check at a fixture instead of depending
# on whatever fonts the machine running the test happens to have.
FONT="${SPATIAL_FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
export SPATIAL_FONT="$FONT"

printf '[spatial] environment self-check\n'

# --- interpreter --------------------------------------------------------------
if v="$(python --version 2>&1)" && [ "${v#Python 3.12.}" != "$v" ]; then
    ok python "$v"
else
    bad python "expected Python 3.12.x, got: ${v:-not on PATH}"
fi

# --- the python stack, probed outside any project -----------------------------
# --no-project so the answer describes the profile rather than whichever folder
# the container is sitting in.
probe="$(mktemp -t spatial-probe-XXXXXXXX.py)"
cat > "$probe" <<'PY'
import io, os, sys
import numpy as np, pandas, openpyxl, cv2, cairosvg
from PIL import Image, ImageFont

print(f"versions cv2={cv2.__version__} pandas={pandas.__version__} numpy={np.__version__}")


def render(text):
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="60" viewBox="0 0 240 60">'
        '<rect width="240" height="60" fill="white"/>'
        f'<text x="5" y="40" font-family="DejaVu Sans" font-size="24">{text}</text></svg>'
    )
    return cairosvg.svg2png(bytestring=svg.encode())


def ink(png_bytes):
    return int((np.array(Image.open(io.BytesIO(png_bytes)).convert("L")) < 128).sum())


probe_text = os.environ.get("SPATIAL_CYRILLIC_PROBE", "Усово")
blank_png = render("")
latin_png = render("Usovo")
cyrillic_png = render(probe_text)
# Missing glyphs are drawn as .notdef boxes, which carry real ink and are blind
# to the codepoint asked for: two different glyphless strings render identically.
# That blindness is the detector. Same length as the Cyrillic probe so the boxes
# line up.
ref_a = render("⿠⿡⿢⿣⿤")
ref_b = render("⿥⿦⿧⿨⿩")

blank, latin, cyrillic = ink(blank_png), ink(latin_png), ink(cyrillic_png)
print(f"cairosvg blank={blank} latin={latin} cyrillic={cyrillic} notdef={ink(ref_a)} interp={sys.executable}")
# Three controls, all load-bearing.
#   blank: a cairosvg PNG has a transparent background, so a bare "are there
#     non-white pixels" test passes on a completely empty render.
#   latin, and a digit-free Cyrillic string: digits render from any font, so
#     "Усово 569" scores 282 ink pixels with every Cyrillic glyph dropped —
#     exactly the failure this probe exists to catch.
#   ref_a/ref_b: missing glyphs are NOT blank — fontconfig/cairo draw .notdef
#     boxes, which carry real ink and are blind to which codepoint was asked
#     for. A container with no Cyrillic font renders "Усово" as five identical
#     boxes, which an ink-threshold check alone cannot tell apart from a real
#     render. The reference must itself be validated: if two different
#     glyphless strings render differently, the chosen codepoints have glyphs
#     in this font and the reference is unusable.
# Measured on a working container: blank 0, latin 390, cyrillic 380.
if blank != 0 or latin <= 0 or cyrillic < latin * 0.5:
    sys.exit(f"cairosvg did not render Cyrillic (blank={blank} latin={latin} cyrillic={cyrillic})")
if ref_a != ref_b:
    sys.exit("the .notdef reference is unusable: the reference codepoints have glyphs in this font")
if cyrillic_png == ref_a:
    sys.exit("cairosvg rendered Cyrillic as .notdef boxes — no Cyrillic-capable font is installed")

font_path = os.environ.get("SPATIAL_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
box = ImageFont.truetype(font_path, 20).getbbox("Усово")
print(f"pillow dejavu bbox={box}")
if box[2] <= box[0]:
    sys.exit("DejaVu measured Cyrillic as zero-width")
PY
# --python-preference only-system so the probe cannot quietly download an
# interpreter and pass while the profile's pinned python is unusable.
if out="$(uv run --no-project --python 3.12 --python-preference only-system \
        --with pandas --with numpy --with opencv-python-headless \
        --with pillow --with cairosvg --with openpyxl \
        python "$probe" 2>&1)"; then
    while IFS= read -r line; do ok python-stack "$line"; done <<<"$out"
else
    bad python-stack "$(printf '%s' "$out" | tail -n 2 | tr '\n' ' ')"
fi
rm -f "$probe"

# --- fonts on disk ------------------------------------------------------------
if [ -f "$FONT" ]; then
    ok fonts "$FONT"
else
    bad fonts "$FONT missing — Cyrillic will be dropped silently"
fi

# --- documents ----------------------------------------------------------------
# A real conversion, not a version comparison: noble's pandoc parses
# --pdf-engine=typst and then fails, which a version check would not catch.
tmp="$(mktemp -d -t spatial-pandoc-XXXXXXXX)"
printf '# Проверка\n\nТекст.\n' > "$tmp/in.md"
if pandoc --pdf-engine=typst "$tmp/in.md" -o "$tmp/out.pdf" 2>"$tmp/err" && [ -s "$tmp/out.pdf" ]; then
    ok pandoc+typst "$(pandoc --version 2>/dev/null | head -n 1)"
else
    bad pandoc+typst "$(tail -n 1 "$tmp/err" 2>/dev/null || echo 'pandoc not on PATH')"
fi
rm -rf "$tmp"

# --- interactive build toolchain and raster back-office -----------------------
# Presence is the assertion; the version text is informational. Binding "prints a
# version" to "exits 0" is a version-dependent assumption — some version flags
# exit non-zero on a perfectly working binary, and under pipefail that fails the
# row for an installed tool. (Measured: noble's poppler 24.02.0 exits 0 for
# `pdftoppm -v`, so this decoupling is insurance against the next version rather
# than a fix for today's.)
for tool in node pnpm pdftoppm convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        bad "$tool" "not on PATH"
        continue
    fi
    case "$tool" in
        pdftoppm) v="$(pdftoppm -v 2>&1 | head -n 1 || true)" ;;
        *)        v="$("$tool" --version 2>&1 | head -n 1 || true)" ;;
    esac
    ok "$tool" "$v"
done

if [ "$fail" -ne 0 ]; then
    printf '[spatial] self-check FAILED\n'
    exit 1
fi
printf '[spatial] self-check passed\n'

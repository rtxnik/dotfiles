#!/usr/bin/env bats
# Gate for the spatial DevPod profile closure.
# Production artifacts: dot_config/workspaces/profiles/spatial/*

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
PROFILE="$REPO_ROOT/dot_config/workspaces/profiles/spatial"

@test "spatial_profile_dir_exists" {
  test -d "$PROFILE"
}

@test "spatial_dockerfile_base_image_matches_fleet" {
  run grep -Fx "FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04" "$PROFILE/Dockerfile"
  [ "$status" -eq 0 ]
}

# Package assertions must see the apt payload, never the rationale comments. The
# Dockerfile explains why each package is there and therefore NAMES most of them
# in prose: a grep over the whole file passes while the install list is empty,
# and the pre-noble absence check below could never pass at all, because the
# comment contains the very token it forbids.
dockerfile_payload() {
  sed -n '/^RUN apt-get update/,/^$/p' "$PROFILE/Dockerfile" | grep -v '^[[:space:]]*#'
}

payload_has() { # <payload> <pkg>
  printf '%s\n' "$1" | grep -qE "(^|[[:space:]])${2}([[:space:]]|\\\\|\$)"
}

# cairosvg renders through libcairo and picks fonts through fontconfig. Without a
# Cyrillic-capable font the text is dropped with no error at all, so the font
# packages are as load-bearing as the library.
@test "spatial_dockerfile_installs_the_cairo_and_font_layer" {
  payload="$(dockerfile_payload)"
  # An empty extraction would make every loop below vacuous.
  [ -n "$payload" ]
  for pkg in libcairo2 fontconfig fonts-dejavu-core fonts-noto-core; do
    payload_has "$payload" "$pkg" || { echo "missing from the apt payload: $pkg"; return 1; }
  done
}

# The t64 ABI transition renamed the package; the pre-noble name installs nothing
# and fails the build.
@test "spatial_dockerfile_uses_the_t64_glib_package" {
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  payload_has "$payload" 'libglib2\.0-0t64'
}

@test "spatial_dockerfile_does_not_use_the_pre_noble_glib_name" {
  # The payload must be non-empty first: an absence check over nothing passes
  # vacuously, which is exactly how this assertion would lie during the red phase.
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  ! payload_has "$payload" 'libglib2\.0-0'
}

@test "spatial_dockerfile_installs_the_opencv_and_raster_layer" {
  payload="$(dockerfile_payload)"
  [ -n "$payload" ]
  for pkg in libgl1 poppler-utils imagemagick; do
    payload_has "$payload" "$pkg" || { echo "missing from the apt payload: $pkg"; return 1; }
  done
}

# A profile that installs a Docker daemon nothing uses pays for it on every
# rebuild.
@test "spatial_devcontainer_omits_docker_in_docker" {
  [ -f "$PROFILE/devcontainer.json" ]
  run grep -F "docker-in-docker" "$PROFILE/devcontainer.json"
  [ "$status" -ne 0 ]
}

@test "spatial_devcontainer_sets_workspace_profile" {
  run jq -r '.containerEnv.WORKSPACE_PROFILE' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "spatial" ]
}

@test "spatial_devcontainer_uses_shared_post_create" {
  run jq -r '.postCreateCommand' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "bash .devcontainer/post-create.sh" ]
}

@test "spatial_devcontainer_forwards_the_preview_ports" {
  run jq -r '.forwardPorts | @csv' "$PROFILE/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "8000,5173" ]
}

# The whole wheel set was verified on 3.12/linux-arm64. `latest` is a standing
# source of "no wheel for the newest interpreter -> build from source -> red".
@test "spatial_mise_pins_python_to_312" {
  run grep -Ex 'python[[:space:]]*=[[:space:]]*"3\.12"' "$PROFILE/mise.toml"
  [ "$status" -eq 0 ]
}

@test "spatial_mise_has_no_floating_python" {
  [ -f "$PROFILE/mise.toml" ]
  run grep -Ex 'python[[:space:]]*=[[:space:]]*"latest"' "$PROFILE/mise.toml"
  [ "$status" -ne 0 ]
}

@test "spatial_mise_carries_the_toolchain" {
  for tool in uv ruff pandoc typst node pnpm jq yq fzf ripgrep fd; do
    grep -qE "^${tool}[[:space:]]*=" "$PROFILE/mise.toml" || { echo "missing: $tool"; return 1; }
  done
}

SCRIPT="$PROFILE/post-create-spatial.sh"

# The bootstrap is exercised against a fixture, never against the real HOME.
setup_spatial_fixture() {
  FIXTURE="$(mktemp -d -t spatial-fixture-XXXXXXXX)"
  WSDIR="$FIXTURE/ws"
  SEEDSRC="$FIXTURE/seed"
  mkdir -p "$WSDIR" "$SEEDSRC" "$FIXTURE/links"
  printf '[project]\nname = "seeded"\n' > "$SEEDSRC/pyproject.toml"
  printf 'help:\n\t@echo ok\n' > "$SEEDSRC/Makefile"
  printf '.venv/\n' > "$SEEDSRC/.gitignore"
  printf '# CLAUDE.md — conversion study\n' > "$SEEDSRC/CLAUDE.md"
  printf '# Conversion study\n' > "$SEEDSRC/README.md"
}

run_bootstrap() {
  env SPATIAL_PROJECT_ROOT="$WSDIR" \
      SPATIAL_SEED_DIR="$SEEDSRC" \
      SPATIAL_LINK_DIR="$FIXTURE/links" \
      SPATIAL_SKIP_SYNC=1 \
      SPATIAL_SKIP_TOOLCHAIN=1 \
      SPATIAL_SKIP_DOCTOR=1 \
      bash "$SCRIPT"
}

teardown() {
  [ -n "${FIXTURE:-}" ] && rm -rf "$FIXTURE"
  return 0
}

@test "spatial_bootstrap_is_executable_and_shellcheck_clean" {
  test -x "$SCRIPT"
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck --severity=warning "$SCRIPT"
    [ "$status" -eq 0 ]
  fi
}

# The shared post-create.sh exports ~/.local/bin but never activates mise, so a
# bootstrap that does not activate it cannot see the pinned toolchain.
@test "spatial_bootstrap_activates_mise" {
  run grep -F 'mise activate bash' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spatial_bootstrap_seeds_an_empty_folder" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/pyproject.toml"
  test -f "$WSDIR/Makefile"
  # A dotfile in the seed must survive the copy — `cp -r src/. dst/` is chosen
  # over a glob for exactly this reason.
  test -f "$WSDIR/.gitignore"
}

@test "spatial_bootstrap_creates_the_directory_skeleton" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  for d in model source scripts tests out docs; do
    test -d "$WSDIR/$d"
  done
}

# A workspace folder is not "already a project" just because something landed
# in it — only pyproject.toml or .git say that. An unrelated file (a stray
# README a user dropped, a downloaded asset) must not stop the seed, and the
# copy's own exit status must not gate the outcome either: `cp -r
# --update=none` still copies everything the seed carries and the completeness
# check, not the copy's status, is what decides.
@test "spatial_bootstrap_seeds_completely_over_a_folder_holding_an_unrelated_file" {
  setup_spatial_fixture
  echo "not a project marker" > "$WSDIR/NOTES.txt"
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -f "$WSDIR/pyproject.toml"
  test -f "$WSDIR/Makefile"
  test -f "$WSDIR/.gitignore"
  test -f "$WSDIR/NOTES.txt"
  for d in model source scripts tests out docs; do
    test -d "$WSDIR/$d"
  done
}

@test "spatial_bootstrap_refuses_to_seed_over_an_existing_project" {
  setup_spatial_fixture
  printf '[project]\nname = "mine"\n' > "$WSDIR/pyproject.toml"
  run run_bootstrap
  [ "$status" -eq 0 ]
  # $output belongs to the LAST `run`, so it has to be captured before any other
  # `run` overwrites it — otherwise the assertion at the end of this test would
  # inspect grep's output and fail forever.
  bootstrap_output="$output"
  # The operator's file is untouched...
  run grep -F 'name = "mine"' "$WSDIR/pyproject.toml"
  [ "$status" -eq 0 ]
  # ...and the seed did not land alongside it.
  [ ! -f "$WSDIR/Makefile" ]
  # The manual path is printed, otherwise the skeleton is unreachable. It must
  # carry the directory skeleton too, not just the copy — mkdir -p never ran
  # for this project since the seed was skipped entirely.
  [[ "$bootstrap_output" == *"cp -r --update=none $SEEDSRC/. $WSDIR/ && mkdir -p $WSDIR/model $WSDIR/source $WSDIR/scripts $WSDIR/tests $WSDIR/out $WSDIR/docs"* ]]
}

@test "spatial_bootstrap_refuses_to_seed_over_a_git_checkout" {
  setup_spatial_fixture
  mkdir -p "$WSDIR/.git"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -f "$WSDIR/pyproject.toml" ]
}

@test "spatial_bootstrap_symlinks_the_conventional_path" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -L "$FIXTURE/links/ws"
  [ "$(readlink "$FIXTURE/links/ws")" = "$WSDIR" ]
}

# A real directory at the conventional path is someone else's data. Capturing
# it with a symlink would point every later instruction at the wrong tree.
@test "spatial_bootstrap_leaves_a_real_directory_at_the_link_path_untouched" {
  setup_spatial_fixture
  mkdir -p "$FIXTURE/links/ws"
  echo "foreign" > "$FIXTURE/links/ws/DATA"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -L "$FIXTURE/links/ws" ]
  test -f "$FIXTURE/links/ws/DATA"
  [[ "$output" == *"WARNING"* ]]
}

@test "spatial_bootstrap_is_idempotent" {
  setup_spatial_fixture
  run run_bootstrap
  [ "$status" -eq 0 ]
  echo "edited by hand" >> "$WSDIR/Makefile"
  run run_bootstrap
  [ "$status" -eq 0 ]
  # Second run must not overwrite work: after the first seed the folder holds a
  # pyproject.toml, so the seed is skipped entirely.
  run grep -F "edited by hand" "$WSDIR/Makefile"
  [ "$status" -eq 0 ]
}

@test "spatial_bootstrap_survives_a_missing_seed_directory" {
  setup_spatial_fixture
  rm -rf "$SEEDSRC"
  run run_bootstrap
  [ "$status" -eq 0 ]
  test -L "$FIXTURE/links/ws"
}

# An interrupted copy that already placed pyproject.toml would make every later
# boot skip the seed as "already a project", leaving the skeleton permanently
# half-built and silent about it.
@test "spatial_bootstrap_reports_an_incomplete_seed" {
  setup_spatial_fixture
  rm -f "$SEEDSRC/Makefile"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"seed is incomplete"* ]]
  [[ "$output" == *"Makefile"* ]]
  [[ "$output" == *"cp -r --update=none $SEEDSRC/. $WSDIR/"* ]]
}

# The shared post-create.sh calls this script with no `|| true` under its own
# set -e, so a non-zero exit here aborts container creation over a symlink.
@test "spatial_bootstrap_survives_an_unwritable_link_dir" {
  setup_spatial_fixture
  mkdir -p "$FIXTURE/ro"
  chmod 500 "$FIXTURE/ro"
  run env SPATIAL_PROJECT_ROOT="$WSDIR" \
      SPATIAL_SEED_DIR="$SEEDSRC" \
      SPATIAL_LINK_DIR="$FIXTURE/ro/links" \
      SPATIAL_SKIP_SYNC=1 SPATIAL_SKIP_TOOLCHAIN=1 SPATIAL_SKIP_DOCTOR=1 \
      bash "$SCRIPT"
  chmod 700 "$FIXTURE/ro"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  # The seed still happened: a link failure must not cost the operator the skeleton.
  test -f "$WSDIR/pyproject.toml"
}

# `seed_project` runs as `seed_project || true`, which suspends errexit for the
# whole function body — without an explicit status check a failed mkdir falls
# through to `return 0` and reports a half-built skeleton as complete.
@test "spatial_bootstrap_reports_a_failed_directory_skeleton" {
  setup_spatial_fixture
  # A regular file where a skeleton directory must go makes mkdir -p fail.
  printf 'not a directory\n' > "$WSDIR/model"
  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not create the directory skeleton"* ]]
}

DOCTOR="$PROFILE/doctor.sh"

@test "spatial_doctor_is_executable_and_shellcheck_clean" {
  test -x "$DOCTOR"
  if command -v shellcheck >/dev/null 2>&1; then
    run shellcheck --severity=warning "$DOCTOR"
    [ "$status" -eq 0 ]
  fi
}

# Two ways this probe can lie, so two controls.
@test "spatial_doctor_cyrillic_check_carries_both_controls" {
  # A cairosvg PNG has a transparent background, so "are there non-white pixels"
  # passes on a completely empty render.
  run grep -E 'blank[[:space:]]*!=[[:space:]]*0' "$DOCTOR"
  [ "$status" -eq 0 ]
  # Digits render from any font, so a probe string carrying digits scores ink
  # with every Cyrillic glyph dropped. The Latin control is what makes the
  # comparison mean something.
  run grep -E 'cyrillic[[:space:]]*<[[:space:]]*latin' "$DOCTOR"
  [ "$status" -eq 0 ]
  # Missing glyphs are not blank: fontconfig/cairo draw .notdef boxes that carry
  # real ink. The reference comparison is what tells a real Cyrillic render
  # apart from a container with no Cyrillic font at all.
  run grep -F 'cyrillic_png == ref_a' "$DOCTOR"
  [ "$status" -eq 0 ]
}

# Digits render from any font, so a digit anywhere in the probe string defeats
# the .notdef comparison: the render stops being byte-identical to the glyphless
# reference and the self-check passes in a container with no Cyrillic support.
# The probe therefore refuses such a string rather than assuming it never gets one.
@test "spatial_doctor_probe_rejects_a_probe_string_containing_digits" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  if [ ! -f /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf ]; then skip "DejaVu absent"; fi
  PROBE="$(mktemp -t spatial-probe-XXXXXXXX.py)"
  sed -n "/^cat > \"\$probe\" <<'PY'\$/,/^PY\$/p" "$DOCTOR" | sed '1d;$d' > "$PROBE"
  [ -s "$PROBE" ]
  run env SPATIAL_CYRILLIC_PROBE='Усово 569' \
      SPATIAL_FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
      uv run --no-project --python 3.12 --python-preference only-system \
      --with pandas --with numpy --with opencv-python-headless \
      --with pillow --with cairosvg --with openpyxl python "$PROBE"
  rm -f "$PROBE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"digits"* ]]
}

# The greps above pin the shape; this runs the real thing. Skipped where uv is
# absent (the CI runner), which is why Task 6 also runs it author-side.
@test "spatial_doctor_probe_renders_cyrillic_in_this_environment" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  if [ ! -f /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf ]; then skip "DejaVu absent"; fi
  PROBE="$(mktemp -t spatial-probe-XXXXXXXX.py)"
  sed -n "/^cat > \"\$probe\" <<'PY'\$/,/^PY\$/p" "$DOCTOR" | sed '1d;$d' > "$PROBE"
  # An empty extraction would make the run below vacuous.
  [ -s "$PROBE" ]
  run env SPATIAL_FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
      uv run --no-project --python 3.12 --python-preference only-system \
      --with pandas --with numpy --with opencv-python-headless \
      --with pillow --with cairosvg --with openpyxl python "$PROBE"
  rm -f "$PROBE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cairosvg blank=0"* ]]
}

# The detector, exercised in the direction that matters. Missing glyphs render as
# .notdef boxes carrying real ink, so an ink-threshold check passes on a
# container with no Cyrillic font at all; only the comparison against a
# same-length glyphless reference catches it.
@test "spatial_doctor_probe_rejects_text_that_renders_as_notdef_boxes" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  if [ ! -f /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf ]; then skip "DejaVu absent"; fi
  PROBE="$(mktemp -t spatial-probe-XXXXXXXX.py)"
  sed -n "/^cat > \"\$probe\" <<'PY'\$/,/^PY\$/p" "$DOCTOR" | sed '1d;$d' > "$PROBE"
  [ -s "$PROBE" ]
  run env SPATIAL_CYRILLIC_PROBE=$'⿪⿫⿬⿭⿮' \
      SPATIAL_FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
      uv run --no-project --python 3.12 --python-preference only-system \
      --with pandas --with numpy --with opencv-python-headless \
      --with pillow --with cairosvg --with openpyxl python "$PROBE"
  rm -f "$PROBE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notdef boxes"* ]]
}

# Version arithmetic says what should work; a conversion says what does. A
# non-empty PDF only proves pandoc ran — it does not prove the Cyrillic
# survived, since silent glyph loss still produces a perfectly non-empty PDF.
# So this also pins the round trip back through pdftotext, anchored on the
# commands rather than on any comment.
@test "spatial_doctor_converts_a_document_rather_than_reading_a_version" {
  run grep -F -- 'pandoc --pdf-engine=typst' "$DOCTOR"
  [ "$status" -eq 0 ]
  run grep -F -- '-s "$tmp/out.pdf"' "$DOCTOR"
  [ "$status" -eq 0 ]
  run grep -F -- 'pdftotext' "$DOCTOR"
  [ "$status" -eq 0 ]
  run grep -F -- "grep -q 'Проверка'" "$DOCTOR"
  [ "$status" -eq 0 ]
}

# The package probe must not depend on the folder the container happens to be
# sitting in: the profile is what is under test, not somebody's project.
@test "spatial_doctor_probes_packages_outside_any_project" {
  run grep -F -- 'uv run --no-project' "$DOCTOR"
  [ "$status" -eq 0 ]
}

@test "spatial_doctor_fails_when_the_toolchain_is_absent" {
  # A stripped PATH has no uv, no pandoc, no node: every probe must fail and the
  # exit code must carry that. This is the assertion that a doctor which always
  # exits 0 cannot survive.
  #
  # HOME points at an empty directory on purpose. doctor.sh prepends
  # $HOME/.local/bin and activates mise when it finds it, and mise's shims would
  # put the real toolchain back on PATH — the test would then measure the
  # machine it runs on instead of the failure path.
  FAKEHOME="$(mktemp -d -t spatial-home-XXXXXXXX)"
  run env -i PATH=/usr/bin:/bin HOME="$FAKEHOME" bash "$DOCTOR"
  rm -rf "$FAKEHOME"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "spatial_doctor_passes_when_every_probe_succeeds" {
  # Stubs prove the accounting, not the environment: a doctor that always exits
  # non-zero fails here, and a doctor that ignores a probe's status fails the
  # test above. The real environment is proven on first boot in the container.
  STUBS="$(mktemp -d -t spatial-stubs-XXXXXXXX)"
  FAKEHOME="$(mktemp -d -t spatial-home-XXXXXXXX)"
  FONTFIX="$FAKEHOME/DejaVuSans.ttf"
  : > "$FONTFIX"
  cat > "$STUBS/python" <<'EOF'
#!/bin/sh
echo "Python 3.12.11"
EOF
  cat > "$STUBS/uv" <<'EOF'
#!/bin/sh
echo "versions cv2=5.0.0 pandas=3.0.5 numpy=2.5.2"
echo "cairosvg blank=0 cyrillic=662"
echo "pillow dejavu bbox=(0, 4, 59, 19)"
EOF
  cat > "$STUBS/pandoc" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in --version) echo "pandoc 3.9.1"; exit 0 ;; esac
done
out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
[ -n "$out" ] && echo "%PDF-1.7 stub" > "$out"
EOF
  # The pandoc stub's output is not a real PDF, so a real pdftotext could not
  # extract anything from it. This stub stands in for the whole "pdftotext
  # recovered the word" half of the round trip, same as the pandoc stub stands
  # in for "typst produced a PDF" — the accounting under test is doctor.sh's,
  # not pdftotext's.
  cat > "$STUBS/pdftotext" <<'EOF'
#!/bin/sh
echo "Проверка" > "$2"
EOF
  for t in node pnpm pdftoppm convert; do
    printf '#!/bin/sh\necho "%s stub 1.0"\n' "$t" > "$STUBS/$t"
  done
  chmod +x "$STUBS"/*
  run env -i PATH="$STUBS:/usr/bin:/bin" HOME="$FAKEHOME" SPATIAL_FONT="$FONTFIX" bash "$DOCTOR"
  rm -rf "$STUBS" "$FAKEHOME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"FAIL"* ]]
}

SEED="$PROFILE/seed"

# chezmoi applies attribute prefixes to every file in the source tree, so a
# literal `.gitignore` here would reach $HOME as `.gitignore` only by accident
# of it being hidden — the source-state name must carry the prefix.
@test "spatial_seed_gitignore_uses_the_chezmoi_prefix" {
  test -f "$SEED/dot_gitignore"
  [ ! -f "$SEED/.gitignore" ]
}

@test "spatial_seed_pins_the_verified_python_floor" {
  run grep -F 'requires-python = ">=3.12,<3.13"' "$SEED/pyproject.toml"
  [ "$status" -eq 0 ]
}

@test "spatial_seed_declares_the_pipeline_dependencies" {
  for pkg in pandas numpy opencv-python-headless pillow cairosvg openpyxl pytest; do
    run grep -F "\"$pkg" "$SEED/pyproject.toml"
    [ "$status" -eq 0 ]
  done
}

# The container has no display and the headless wheel drops the whole GL
# dependency chain; the full wheel is available by hand, which is why the image
# still carries libgl1.
@test "spatial_seed_does_not_request_the_gui_opencv_wheel" {
  [ -f "$SEED/pyproject.toml" ]
  run grep -E '"opencv-python[^-]' "$SEED/pyproject.toml"
  [ "$status" -ne 0 ]
}

@test "spatial_seed_resolves_with_uv" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  WORK="$(mktemp -d -t spatial-lock-XXXXXXXX)"
  cp "$SEED/pyproject.toml" "$WORK/"
  run bash -c "cd '$WORK' && uv lock"
  rm -rf "$WORK"
  [ "$status" -eq 0 ]
}

@test "spatial_seed_makefile_exposes_the_pipeline_targets" {
  for target in help sync csv svg xlsx capacity test doctor all clean; do
    run grep -E "^${target}:" "$SEED/Makefile"
    [ "$status" -eq 0 ]
  done
}

# pytest's exit 5 ("no tests ran") is the design's own forbidden shape when
# mapped to success unconditionally: "a test file that passes because it has
# nothing to check reports green for no reason." It must stay success only
# when tests/ carries no Python files at all.
setup_make_test_fixture() {
  MTFIXTURE="$(mktemp -d -t spatial-make-test-XXXXXXXX)"
  cp "$SEED/Makefile" "$MTFIXTURE/"
  cat > "$MTFIXTURE/pyproject.toml" <<'EOF'
[project]
name = "make-test-fixture"
version = "0.1.0"
requires-python = ">=3.12,<3.13"
dependencies = []

[dependency-groups]
dev = ["pytest>=8.3"]
EOF
}

@test "spatial_seed_make_test_passes_with_no_test_files_at_all" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  setup_make_test_fixture
  run make -C "$MTFIXTURE" test
  rm -rf "$MTFIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no model invariants written yet"* ]]
}

# The case that used to be silently green: tests/ holds a Python file, but it
# collects zero test items (a helper module, a fixture-only file, a typo'd test
# name). pytest still exits 5 here — the old code treated every exit 5 as
# success, so this reported green with a stub sitting in tests/ that nothing
# ever ran. It must fail now.
@test "spatial_seed_make_test_fails_when_tests_dir_has_a_file_but_collects_nothing" {
  if ! command -v uv >/dev/null 2>&1; then skip "uv not installed"; fi
  setup_make_test_fixture
  mkdir -p "$MTFIXTURE/tests"
  printf 'def helper():\n    return 1\n' > "$MTFIXTURE/tests/util.py"
  run make -C "$MTFIXTURE" test
  rm -rf "$MTFIXTURE"
  [ "$status" -ne 0 ]
}

# `all` documents itself as "rebuild every derived artifact", so it must depend
# on every artifact target — a partial `all` is a rebuild that quietly leaves one
# derived file stale, which is the exact failure this project's rules forbid.
@test "spatial_seed_makefile_all_covers_every_artifact_target" {
  line="$(grep -E '^all:' "$SEED/Makefile")"
  [ -n "$line" ]
  for target in csv svg xlsx capacity; do
    [[ "$line" == *" $target"* ]] || { echo "all: does not depend on $target"; return 1; }
  done
}

# A target whose script has not been written yet must say so by name rather than
# silently produce nothing.
@test "spatial_seed_makefile_names_a_missing_script" {
  WORK="$(mktemp -d -t spatial-make-XXXXXXXX)"
  cp "$SEED/Makefile" "$WORK/"
  run make -C "$WORK" -n csv
  [ "$status" -ne 0 ]
  [[ "$output" == *"scripts/export_csv.py"* ]]
  rm -rf "$WORK"
}

@test "spatial_seed_makefile_names_the_script_in_its_recipe" {
  WORK="$(mktemp -d -t spatial-make-XXXXXXXX)"
  cp "$SEED/Makefile" "$WORK/"
  mkdir -p "$WORK/scripts"
  echo "print('ok')" > "$WORK/scripts/export_csv.py"
  run make -C "$WORK" -n csv
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/export_csv.py"* ]]
  rm -rf "$WORK"
}

@test "spatial_seed_claude_md_states_the_load_bearing_rules" {
  for phrase in "geometry.json" "39 dpi" "y_svg = -Y_mm" "cv2.putText" "model_core.json"; do
    run grep -F "$phrase" "$SEED/CLAUDE.md"
    [ "$status" -eq 0 ]
  done
}

# The rules file documents `make all`. If its comment and the Makefile's own
# dependency list disagree, a reader trusting the rules file expects the wrong
# set of artifacts to be rebuilt — which is how this drifted in the first place.
@test "spatial_seed_claude_md_rebuild_line_matches_make_all" {
  deps="$(grep -E '^all:' "$SEED/Makefile" | sed 's/^all:[[:space:]]*//; s/#.*//')"
  [ -n "$deps" ]
  line="$(grep -F 'make all' "$SEED/CLAUDE.md")"
  [ -n "$line" ]
  for d in $deps; do
    [[ "$line" == *"$d"* ]] || { echo "make all depends on $d, not named in CLAUDE.md: $line"; return 1; }
  done
}

@test "spatial_readme_documents_the_load_bearing_decisions" {
  for phrase in "libglib2.0-0t64" "3.1.11" "opencv-python-headless" "policy.xml"; do
    run grep -F "$phrase" "$PROFILE/README.md"
    [ "$status" -eq 0 ]
  done
}

# The rule that keeps unpushed work off container-local storage is the one a
# reader most needs and least expects.
@test "spatial_readme_states_where_the_work_lives" {
  run grep -F 'host-mounted' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
  run grep -F 'does not survive' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
}

# The copy alone leaves the six directories missing — they are created
# separately because git cannot track empty directories — so the documented
# manual path must carry both commands, not just the copy.
@test "spatial_readme_documents_the_manual_seed_path" {
  run grep -F 'cp -r --update=none ~/.config/workspaces/profiles/spatial/seed/. .' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
  run grep -F 'mkdir -p model source scripts tests out docs' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
}

@test "spatial_is_listed_in_the_profiles_index" {
  run grep -E '^\| `spatial` \|' "$REPO_ROOT/dot_config/workspaces/README.md"
  [ "$status" -eq 0 ]
}

# The bootstrap, the self-check and the seed all arrive over the network on first
# boot, and the shared script fails open when they do not. An operator who does
# not know the symptom reads a silent container as a working one.
@test "spatial_readme_states_the_first_boot_network_dependency" {
  run grep -F 'First boot needs network' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
  run grep -F 'no `[spatial]` lines at all' "$PROFILE/README.md"
  [ "$status" -eq 0 ]
}

# .chezmoiignore already excludes scripts/ci, scripts/lib and
# scripts/tests/test-*.sh under "repo tooling must never be copied into $HOME".
# The rule simply misses the .bats extension, so 14 gate files are applied into
# every machine's home directory today and this PR would add a fifteenth.
@test "chezmoiignore_excludes_the_repo_test_suites" {
  run grep -Ex 'scripts/tests' "$REPO_ROOT/.chezmoiignore"
  [ "$status" -eq 0 ]
}

# The rule this branch completed covers scripts/tests only. The root tests/
# directory has never had an entry and is out of scope here; asserting the
# repo-wide count would encode a claim this change does not make.
@test "chezmoiignore_keeps_scripts_tests_out_of_home" {
  if ! command -v chezmoi >/dev/null 2>&1; then skip "chezmoi not installed"; fi
  managed="$(chezmoi managed --source "$REPO_ROOT")"
  [ -n "$managed" ]
  run bash -c "printf '%s\n' \"\$1\" | grep '\\.bats\$' | grep -c '^scripts/tests/'" _ "$managed"
  [ "$output" = "0" ]
}

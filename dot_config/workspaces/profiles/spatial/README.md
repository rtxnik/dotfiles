# spatial Profile

Environment for turning a low-resolution architectural raster into a numeric
model and every artifact derived from it — CSV mirrors, XLSX, generated SVG
plans, documents, and a single-file parametric interactive.

The profile is named for the work, not for a client: nothing in it is specific
to one building.

## Toolchain

| Tool | Why |
|------|-----|
| Python 3.12 (pinned) | The whole wheel set — opencv, pandas, numpy, cairosvg, Pillow, openpyxl — was verified on 3.12/linux-arm64. `latest` invites "no wheel → build from source" on the newest interpreter |
| uv, ruff | Environment resolution and linting; packages live in the project's `pyproject.toml`, never in this image |
| pandoc + typst | Markdown is the working format, docx and PDF are delivery. typst is the PDF engine that avoids a LaTeX distribution |
| Node LTS + pnpm | Builds the parametric interactive into one HTML file |
| jq, yq, fzf, ripgrep, fd | Fleet standard |
| libcairo2, fontconfig, DejaVu, Noto | cairosvg's rendering path, and the fonts without which Cyrillic disappears |
| libglib2.0-0t64, libgl1 | OpenCV's libraries |
| poppler-utils, imagemagick | Raster back-office: PDF page extraction, batch scan preparation |

Deliberately absent: docker-in-docker (nothing here needs a daemon), and any
CAD/BIM/3D tooling — on a ~39 dpi source those produce invented geometry
presented as fact.

## Load-bearing details

- **`libglib2.0-0t64`, not `libglib2.0-0`.** Ubuntu 24.04's t64 ABI transition
  renamed the package. The old name does not exist on noble and fails the build.
- **pandoc comes from mise, not apt.** Noble ships 3.1.3; `--pdf-engine=typst`
  landed in 3.1.11. The apt package parses the flag and then fails.
- **The seed pins `opencv-python-headless`.** The container has no display, and
  the headless wheel drops the GL dependency chain. `libgl1` is installed anyway
  so a manual swap to the full wheel works.
- **ImageMagick 6's `policy.xml` blocks PDF read/write** on Ubuntu. Use
  `poppler-utils` (`pdftoppm`) for PDF pages rather than loosening the policy.

## Where the work lives

The bootstrap symlinks `~/projects/<workspace>` to the **host-mounted workspace
folder** and works there. `~/projects` is container-local storage: it **does not survive**
a rebuild or `ws delete`, so a checkout there puts unpushed work one
container lifecycle away from unrecoverable loss.

If `~/projects/<workspace>` already exists as a real directory, the bootstrap
leaves it alone and warns rather than capturing the path.

## The seed

On first boot, a workspace folder holding neither `pyproject.toml` nor `.git`
receives a skeleton: `pyproject.toml` with the verified dependency set, a
`Makefile` whose targets rebuild every derived artifact, `.gitignore`,
`CLAUDE.md` with the project rules, a `README.md`, and the directory layout.

A folder that already holds a project is never touched. To apply the skeleton by
hand afterwards:

```bash
cp -r --update=none ~/.config/workspaces/profiles/spatial/seed/. .
mkdir -p model source scripts tests out docs
```

The copy alone is not the whole skeleton: the six directories above are created
separately by the bootstrap because git cannot track empty directories.

Analytic scripts and model invariants are **not** seeded. They belong to a model
that does not exist yet, and a test file that passes because it has nothing to
check reports green for no reason.

## First boot needs network

`ws new` copies the three profile files — `devcontainer.json`, `Dockerfile` and `mise.toml` —
plus the fleet's shared `post-create.sh` into the workspace's `.devcontainer/`. What does not
arrive is anything profile-specific: the bootstrap, the self-check and the seed are read
**inside** the container from `~/.config/workspaces/profiles/spatial/`, which the shared
post-create materialises by applying the dotfiles from GitHub. Without network on first boot
none of them exist — and the shared script's chezmoi installer swallows that failure, so the
container comes up with the correct image, no symlink, no seed, no self-check, and no complaint.

The symptom is precise: the container-create log contains **no `[spatial]` lines at all**. Recover by
re-creating the workspace with network, or by running
`sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/rtxnik/dotfiles.git`
inside the container and then
`bash ~/.config/workspaces/profiles/spatial/post-create-spatial.sh` from the workspace folder.

This is a property of the shared bootstrap that every profile in the fleet inherits. It is recorded
here rather than patched here.

## Proving the container

```bash
make doctor                                               # from the project
bash ~/.config/workspaces/profiles/spatial/doctor.sh      # from anywhere
```

The self-check converts a real document through typst and renders real Cyrillic
through cairosvg — with a blank control, because a cairosvg PNG has a
transparent background and a naive "are there non-white pixels" test passes on a
completely empty render. It exits non-zero if any probe fails.

## Traps this environment exists to close

1. `cv2.putText` cannot draw Cyrillic — OpenCV's Hershey fonts have no Cyrillic
   glyphs and labels come out as `??`. Use Pillow with DejaVu Sans or Noto Sans.
2. `cairosvg` drops Cyrillic silently without a Cyrillic-capable font.
3. SVG authored in millimetres means stroke widths are millimetres too:
   `stroke-width="240"` is 240 mm and looks right at plan scale.
4. The Y axis is inverted (`y_svg = -Y_mm`), so the viewBox origin is negative.
5. Raster work needs separate X and Y scales — a 0.4-0.5 % anisotropic scan puts
   up to 200 mm of error on the overall dimension under a single scale.

## Usage

```bash
ws new <name> spatial        # add --proxy for proxy networking
ws start <name>
ws ssh <name>
```

# CLAUDE.md — conversion study

## The rule that makes everything else work

`model/geometry.json` is the only file edited by hand. Every CSV, XLSX, SVG,
document and interactive is regenerated from it by a script under `scripts/`.
An artifact that cannot be rebuilt in one `make` run is a copy, not an artifact
— and a copy that disagrees with the model is exactly the defect this study
exists to avoid.

## Precision floor

The source is a raster at ~39 dpi with no text layer. Wall types, openings and
room outlines are not recoverable from it. No output may imply precision the
source does not carry: no CAD tracing, no BIM, no 3D view. A number that is not
in the model is not invented — it is recorded as unknown.

## Units and axes

Millimetres everywhere. The SVG viewBox is in millimetres, so stroke widths are
too: `stroke-width="240"` means 240 mm and reads correctly at plan scale. The Y
axis is inverted (`y_svg = -Y_mm`), so the viewBox origin is negative.

Raster work uses separate X and Y scales: the scan is 0.4-0.5 % anisotropic, and
a single scale puts up to 200 mm of error on the overall dimension.

## Traps that have already cost time

- `cv2.putText` cannot draw Cyrillic — OpenCV's Hershey fonts carry no Cyrillic
  glyphs and labels come out as `??`. Use Pillow with DejaVu Sans.
- `cairosvg` drops Cyrillic silently when no Cyrillic-capable font is installed.
- The interactive imports `model_core.json` and hard-codes no numbers. Two model
  edits later, a hard-coded one states something false and states it
  confidently.

## Language

Discussion in Russian. Code, comments, commit messages and documents in English.

## Rebuilding

```bash
make sync     # resolve the environment
make all      # csv + svg + xlsx + capacity from the model
make test     # model invariants
make doctor   # environment self-check
```

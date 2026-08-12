# Conversion study

Decision material, not a design project: a numeric model of the building and
everything derived from it.

```
source/            raster sheets, ~39 dpi — the precision floor
   |  opencv + calibration
   v
model/geometry.json   <- the only file edited by hand
   |
   +-- scripts/export_csv.py    -> rooms/blocks/axes/walls/voids.csv
   +-- scripts/build_xlsx.py    -> rooms.xlsx
   +-- scripts/build_svg.py     -> plans/*.svg
   +-- scripts/capacity.py      -> capacity matrix
   +-- model_core.json          -> the parametric interactive
             |
        pytest: model invariants
```

`make help` lists every target. The rules that bind the work are in
`CLAUDE.md`.

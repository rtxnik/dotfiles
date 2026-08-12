# Every derived artifact is rebuilt from model/geometry.json. Nothing under
# out/ is edited by hand: an artifact that cannot be regenerated is a copy, and
# a copy that disagrees with the model is the defect this project exists to
# avoid.
PY := uv run python
DOCTOR := $(HOME)/.config/workspaces/profiles/spatial/doctor.sh

.DEFAULT_GOAL := help
.PHONY: help sync csv svg xlsx capacity test doctor all clean

help:  ## show this list
	@grep -E '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t14

sync:  ## resolve the python environment
	uv sync

csv: scripts/export_csv.py  ## model -> rooms/blocks/axes/walls/voids.csv
	$(PY) $<

svg: scripts/build_svg.py  ## model -> plans/*.svg
	$(PY) $<

xlsx: scripts/build_xlsx.py  ## model -> rooms.xlsx
	$(PY) $<

capacity: scripts/capacity.py  ## capacity matrix
	$(PY) $<

test:  ## model invariants
	@uv run pytest -q; rc=$$?; \
	if [ $$rc -eq 5 ] && [ -z "$$(find tests -name '*.py' -print -quit 2>/dev/null)" ]; then \
		echo "no model invariants written yet"; \
	else \
		exit $$rc; \
	fi

doctor:  ## environment self-check, provided by the spatial profile
	@test -f $(DOCTOR) || { echo "profile self-check not found at $(DOCTOR)"; exit 1; }
	@bash $(DOCTOR)

all: csv svg xlsx capacity  ## rebuild every derived artifact

clean:  ## remove generated output
	rm -rf out

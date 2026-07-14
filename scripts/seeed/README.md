# Seeed carrier board build helpers

These helpers support all Seeed machines in
`layers/meta-seeed/conf/machine`. Prepare one build directory per machine;
the most recently prepared directory becomes active for later commands.

```bash
./scripts/seeed/build.sh machines
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-industrial-orin-j401 \
  --build-dir build-seeed-industrial-j401
./scripts/seeed/build.sh current
./scripts/seeed/build.sh metadata
./scripts/seeed/build.sh dtb
./scripts/seeed/build.sh bootfiles
./scripts/seeed/build.sh image
./scripts/seeed/prepare-flash.sh
./scripts/seeed/validate-all-machines.sh
```

The validation script parses all 16 machines and compiles one complete DT set
for each SoC family (`tegra234` and `tegra264`). It does not claim physical
flash or peripheral validation.

Use a separate build directory per machine when switching targets. Do not reuse
an existing build directory for a different `MACHINE`. An explicit
`build.sh --build-dir` selects that prepared directory and makes it active for
later commands. Add `--no-activate` for a one-command temporary selection;
`--machine` verifies the prepared directory's machine.

The remaining workspace and flash helpers still accept their documented cache,
image, archive, and extraction options.

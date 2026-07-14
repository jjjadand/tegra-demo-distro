# Seeed carrier board build helpers

These helpers support all Seeed machines in
`layers/meta-seeed/conf/machine`. Select a target with `--machine` or
`MACHINE=...`.

```bash
./scripts/seeed/build.sh machines
./scripts/seeed/build.sh metadata --machine recomputer-industrial-orin-j401
./scripts/seeed/build.sh dtb --machine recomputer-mini-agx-orin-j501x
./scripts/seeed/build.sh bootfiles --machine recomputer-thor-carrier-j601
./scripts/seeed/validate-all-machines.sh
```

The validation script parses all 16 machines and compiles one complete DT set
for each SoC family (`tegra234` and `tegra264`). It does not claim physical
flash or peripheral validation.

The remaining workspace and flash helpers still accept their documented
machine, build, cache, image, and extraction options.

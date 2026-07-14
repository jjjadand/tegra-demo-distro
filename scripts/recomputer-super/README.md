# reComputer Super build helpers

These scripts keep source, build output, shared downloads, sstate, and extracted
flash files separate. They intentionally do not install host packages or invoke
`sudo ./initrd-flash` automatically.

```bash
./scripts/recomputer-super/prepare-workspace.sh
./scripts/recomputer-super/discover-l4t-boards.sh --l4t-dir ../Linux_for_Tegra
./scripts/recomputer-super/build.sh metadata
./scripts/recomputer-super/build.sh dtb
./scripts/recomputer-super/build.sh image
./scripts/recomputer-super/prepare-flash.sh
```

Use `--help` on each script for alternate build, cache, image, machine, and
extraction directories.

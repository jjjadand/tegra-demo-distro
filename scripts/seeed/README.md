# Seeed carrier board build helpers

These helpers support all Seeed machines in
`layers/meta-seeed/conf/machine`. Prepare one build directory per machine and,
for AGX Orin, per module SKU; the most recently prepared directory becomes
active for later commands.

```bash
./scripts/seeed/build.sh machines
./scripts/seeed/prepare-workspace.sh \
  --machine recomputer-orin-super-j401 \
  --build-dir build-seeed-super-j401
./scripts/seeed/build.sh current
./scripts/seeed/build.sh all
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
an existing build directory for a different `MACHINE` or AGX Orin module SKU.
AGX Orin machines require `prepare-workspace.sh --module-sku`; the selection is
stored in `conf/seeed-machine.conf` and reused by later commands. An explicit
`build.sh --build-dir` selects that prepared directory and makes it active for
later commands. Add `--no-activate` for a one-command temporary selection;
`--machine` verifies the prepared directory's machine.

`build.sh all` runs metadata validation, DTB/DTBO compilation, bootfiles
installation checks, and the complete image build in order. It stops at the
first failed stage.

`build.sh current` prints both the carrier `MACHINE` and the fixed module SKU.
`prepare-flash.sh` verifies that the tegraflash archive carries the same SKU
before presenting the flash command.

The remaining workspace and flash helpers still accept their documented cache,
image, archive, and extraction options.

## Initrd flash USB debug workflow

If `initrd-flash` stops after `Sending blob` and keeps printing dots after
`Waiting for USB storage device flashpkg`, do not treat it as slow rootfs
writing. At that point the host is waiting for the Jetson initrd to enumerate a
temporary USB mass-storage device; partition writing has not started yet.

Use this sequence to isolate the failure:

1. Confirm RCM download completed in `log.initrd-flash.*`: `Sending bct_*`,
   `Sending mb1`, `Sending blob`, with no transfer error.
2. Run `lsusb`. If the device remains `0955:7x23 NVIDIA Corp. APX` and no new
   `/dev/sdX` appears, the target did not reach initrd USB device mode.
3. Inspect the compiled DTB, not only the DTS source. Later NVIDIA module DTSI
   includes can override an earlier `status = "okay"`.
4. For Tegra234, verify all three nodes together:

   ```bash
   fdtget -t s board.dtb \
     /bus@0/padctl@3520000/pads/usb2/lanes/usb2-0 status
   fdtget -t s board.dtb \
     /bus@0/padctl@3520000/ports/usb2-0 status
   fdtget -t s board.dtb /bus@0/usb@3550000 status
   ```

   All three values must be `okay`: the USB2 PHY lane, OTG port, and XUDC
   controller form one device-mode path. Host USB additionally requires the
   enabled XHCI controller and matching PHY list.

The J501 carrier DTS files include `tegra234-j501x-usb-enabled.dtsi` after the
module DTSI so module-SKU overrides cannot silently disable the final USB
topology. The `seeed-devicetree` compile task checks the final Tegra234 and
Tegra264 DTBs and fails immediately if the initrd-flash path is missing or
disabled.

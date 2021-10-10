# Table of Contents <!-- omit in toc -->
- [Introduction](#introduction)
  - [Terminoligy / Abbr for this doc.](#terminoligy--abbr-for-this-doc)
  - [BananaPi M64](#bananapi-m64)
    - [Build](#build)
    - [Boot](#boot)
    - [Snap](#snap)
  - [bbxm](#bbxm)


<!-- grouping links -->


# Introduction


## Terminoligy / Abbr for this doc.
-   Project - Software project
-   Source tree - The directory structure for this project
-   Host - The machine used to build this project
-   Target - The machine used to run outcome of this project
-   Target runtime - The running target environemnt
-   Builder - Script or tools participants to build this project
-   Script - Executable source (mostly clear text)
-   Tool/Util - Software tool (application)

## BananaPi M64

### Build
-   Ubuntu 20.04
-   Terminal from RS232 3.3v
-   USB for `sunxi-fel`

### Boot
Bootloader combind BL31 from ARM Trusted Firmware (ATF), System Control Processor (SCP) from **Crust**, SPL and U-Boot. Refer to `u-boot/board/sunxi/README.sunxi64` for detail.

Boot ROM (BROM) load bootloader from SD card offset 8k:

    dd if=build/uboot/u-boot-sunxi-with-spl.bin of=/dev/sd?? bs=1024 seek=8

The uboot.env size must match menuconfig, otherwize lead to CRC error when boot

    mkenvimage -s 131072 -o uboot.env uboot.env.txt

### Snap
    make linux_BUILDDIR=`pwd`/build/linux-armbian DOTCFG=`pwd`/armbian_linux-sunxi64-current.config dist && make dist_sd && sync ; sync



----
## bbxm

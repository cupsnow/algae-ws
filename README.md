## BananaPi M64

### Build
-   Ubuntu 20.04
-   Terminal from RS232 3.3v
-   USB for `sunxi-fel`

### Boot
Bootloader combind BL31 from ARM Trusted Firmware (ATF), System Control Processor (SCP) from **Crust**, SPL and U-Boot. Refer to `u-boot/board/sunxi/README.sunxi64` for detail.

Boot ROM (BROM) load bootloader from SD card offset 8k:

    dd if=build/uboot/u-boot-sunxi-with-spl.bin of=/dev/sdd bs=1024 seek=8

The uboot.env size must match menuconfig, otherwize lead to CRC error when boot

    mkenvimage -s 131072 -o uboot.env uboot.env.txt

### Snap
    make linux_BUILDDIR=`pwd`/build/linux-armbian DOTCFG=`pwd`/armbian_linux-sunxi64-current.config dist && make dist_sd && sync ; sync



----
## bbxm

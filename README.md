# Table of Contents <!-- omit in toc -->
- [Setup](#setup)
- [Boot](#boot)
	- [Download to memory and execute](#download-to-memory-and-execute)
- [Garage](#garage)


<!-- grouping links -->

# Setup
- Ubuntu 20.04
- Terminal from RS232 3.3v
- USB for `sunxi-fel`

# Boot
Bootloader combind BL31 from ARM Trusted Firmware (ATF), System Control Processor (SCP) from **Crust**, SPL and U-Boot. Refer to [u-boot/board/sunxi/README.sunxi64](../uboot/board/sunxi/README.sunxi64) for detail.

Boot ROM (BROM) load bootloader from SD card offset 8k:

    dd if=build/uboot/u-boot-sunxi-with-spl.bin of=/dev/sd?? bs=1024 seek=8

The uboot.env size must match menuconfig, otherwize lead to CRC error when boot

    mkenvimage -s 131072 -o uboot.env uboot.env.txt

## Download to memory and execute

- Plug usb otg cable which support enough current.
- Press FEL then plug power to enter FEL mode
- Run this

	  ./tool/bin/sunxi-fel -v -p uboot ../build/uboot-bpi/u-boot-sunxi-with-spl.bin \
	      write 0x40200000 ../build/linux-bpi/arch/arm64/boot/Image.gz \
	      write 0x4fa00000 destdir/boot/sun50i-a64-bananapi-m64.dtb \
	      write 0x4ff00000 destdir/uInitramfs

- When boot to uboot

      setenv bootargs console=ttyS0,115200n8 root=/dev/ram0
	  booti 0x40200000 0x4ff00000 0x4fa00000

	> booti will unpack uInitramfs to find size; if use initramfs.cpio.gz, booti 2nd argument need manually append filesize

# Garage

```
make linux_BUILDDIR=`pwd`/build/linux-armbian DOTCFG=`pwd`/armbian_linux-sunxi64-current.config dist && make dist_sd && sync ; sync
```


```
mmc rescan && fatls mmc 0:1 &&
setenv bootargs console=ttyS0,115200n8 root=/dev/ram0
fatload mmc 0:1 0x40200000 Image.gz &&
fatload mmc 0:1 0x4fa00000 sun50i-a64-bananapi-m64.dtb &&
fatload mmc 0:1 0x4ff00000 initramfs.cpio.gz &&
booti 0x40200000 ${fileaddr}:${filesize} 0x4fa00000
```
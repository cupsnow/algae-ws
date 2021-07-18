#------------------------------------
#
PROJDIR?=$(abspath $(firstword $(wildcard ./builder ../builder))/..)
-include $(PROJDIR:%=%/)builder/site.mk
include $(PROJDIR:%=%/)builder/proj.mk

.DEFAULT_GOAL=all

APP_ATTR_xm?=xm
export APP_ATTR?=$(APP_ATTR_xm)

APP_PLATFORM=$(strip $(filter xm bbb,$(APP_ATTR)))

ifneq ("$(strip $(filter xm bbb,$(APP_ATTR)))","")
TOOLCHAIN_PATH=$(HOME)/07_sw/gcc-arm-none-linux-gnueabihf
CROSS_COMPILE=arm-none-linux-gnueabihf-
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin) $(PROJDIR)/tool/bin
endif

export PATH:=$(call ENVPATH,$(EXTRA_PATH))

$(info Makefile ... APP_ATTR: $(APP_ATTR), \
  APP_PLATFORM: $(APP_PLATFORM), \
  PATH=$(PATH))

#------------------------------------
#
dtc_DIR?=$(HOME)/02_dev/dtc
dtc_BUILDDIR?=$(BUILDDIR)/dtc
dtc_MAKE?=$(MAKE) V=1 -C $(dtc_BUILDDIR)

$(dtc_BUILDDIR):
	git clone $(dtc_DIR) $@

dtc_clean dtc_distclean:
	$(RM) $(dtc_BUILDDIR)

dtc: | $(dtc_BUILDDIR)
	$(dtc_MAKE)

dtc_%: | $(dtc_BUILDDIR)
	$(dtc_MAKE) $(@:dtc_%=%)

#------------------------------------
# dep: apt install dvipng
#
$(BUILDDIR)/pyenv:
	virtualenv -p python3 $(BUILDDIR)/pyenv
	echo "Install package required for uboot and linux docs"
	. $(BUILDDIR)/pyenv/bin/activate && \
	  python --version && \
	  pip install sphinx sphinx_rtd_theme six

#------------------------------------
# uboot_tools-only_defconfig uboot_tools-only
#
uboot_BUILDDIR?=$(BUILDDIR)/uboot
uboot_DIR?=$(HOME)/02_dev/u-boot
uboot_DEF_MAKE?=$(MAKE) ARCH=arm \
  CROSS_COMPILE=$(CROSS_COMPILE)
uboot_DEF_MAKE+=CONFIG_TOOLS_DEBUG=1
uboot_MAKE?=$(uboot_DEF_MAKE) -C $(uboot_BUILDDIR)

xm_uboot_defconfig:
	$(uboot_DEF_MAKE) O=$(uboot_BUILDDIR) -C $(uboot_DIR) \
	  omap3_beagle_defconfig

$(uboot_BUILDDIR)/.config:
	$(MAKE) $(APP_PLATFORM)_uboot_defconfig

uboot_distclean:
	$(RM) $(uboot_BUILDDIR)

# ubuntu package required?  texlive-latex-extra
uboot_htmldocs: | $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(uboot_MAKE) $(@:uboot_%=%)

# NO recipe but prerequisite for some submake target  
uboot $(addprefix uboot_,tools): $(uboot_BUILDDIR)/.config

uboot:
	$(uboot_MAKE)

uboot_%:
	$(uboot_MAKE) $(@:uboot_%=%)

#------------------------------------
#
linux_BUILDDIR?=$(BUILDDIR)/linux
linux_DIR?=$(HOME)/02_dev/linux
linux_DEF_MAKE?=$(MAKE) ARCH=arm LOADADDR=$(LOADADDR) \
  CROSS_COMPILE=$(CROSS_COMPILE) \
  CONFIG_INITRAMFS_SOURCE="$(CONFIG_INITRAMFS_SOURCE)"
#linux_DEF_MAKE+=V=1
linux_MAKE=$(linux_DEF_MAKE) -C $(linux_BUILDDIR)

xm_linux_defconfig:
	$(linux_DEF_MAKE) O=$(linux_BUILDDIR) -C $(linux_DIR) \
	  omap2plus_defconfig # multi_v7_defconfig, omap2plus_defconfig

$(linux_BUILDDIR)/.config:
	$(MAKE) $(APP_PLATFORM)_linux_defconfig

linux_distclean:
	$(RM) $(linux_BUILDDIR)

# ubuntu package required?  texlive-latex-extra
linux_htmldocs: | $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(linux_MAKE) $(@:linux_%=%)

# NO recipe but prerequisite for some submake target  
linux $(addprefix linux_,tools uImage zImage bzImage dtbs): $(linux_BUILDDIR)/.config

linux:
	$(linux_MAKE)

linux_%:
	$(linux_MAKE) $(@:linux_%=%)

#------------------------------------
#
busybox_BUILDDIR?=$(BUILDDIR)/busybox
busybox_DIR?=$(HOME)/02_dev/busybox
busybox_DEF_MAKE=$(MAKE) ARCH=arm \
  CROSS_COMPILE=$(CROSS_COMPILE)
busybox_MAKE=$(busybox_DEF_MAKE) -C $(busybox_BUILDDIR)

xm_busybox_defconfig:
	[ -d $(busybox_BUILDDIR) ] || $(MKDIR) $(busybox_BUILDDIR)
	$(busybox_DEF_MAKE) O=$(busybox_BUILDDIR) -C $(busybox_DIR) \
	  defconfig

$(busybox_BUILDDIR)/.config:
	$(MAKE) $(APP_PLATFORM)_busybox_defconfig

busybox_distclean:
	$(RM) $(busybox_BUILDDIR)

busybox: $(busybox_BUILDDIR)/.config
	$(busybox_MAKE)

busybox_%:
	$(busybox_MAKE) $(@:busybox_%=%)

#------------------------------------
# dep: uboot uboot_tools linux_bzImage linux_dtbs busybox dtc
#
DESTDIR_BOOT=$(DESTDIR)/boot
BUILDDIR_INITRAMFS?=$(BUILDDIR)/initramfs
BUILDDIR_INITRAMFS_ROOTFS=$(BUILDDIR_INITRAMFS)/rootfs
BUILDDIR_ROOTFS=$(BUILDDIR)/rootfs

xm_boot_tools:
	[ -d $(PROJDIR)/tool/bin ] || $(MKDIR) $(PROJDIR)/tool/bin
	$(CP) $(uboot_BUILDDIR)/tools/mkimage $(PROJDIR)/tool/bin/
	$(dtc_MAKE) DESTDIR= PREFIX=$(PROJDIR)/tool install

xm_boot_initramfs: xm_boot_SYSROOT?=$(shell $(CC) -print-sysroot)
xm_boot_initramfs:
	[ -d $(BUILDDIR_INITRAMFS_ROOTFS) ] || $(MKDIR) $(BUILDDIR_INITRAMFS_ROOTFS)
	echo -n "" > $(BUILDDIR_INITRAMFS)/devlist
	echo "dir /dev 0755 0 0" >> $(BUILDDIR_INITRAMFS)/devlist
	echo "nod /dev/console 0600 0 0 c 5 1" >> $(BUILDDIR_INITRAMFS)/devlist
	$(busybox_MAKE) CONFIG_PREFIX=$(BUILDDIR_INITRAMFS_ROOTFS) \
	  install
	for i in $(PROJDIR)/prebuilt/common/ \
	  $(PROJDIR)/prebuilt/initramfs/ ; do \
	    [ -n "`ls -A $${i}`" ] && $(CP) $${i}/* $(BUILDDIR_INITRAMFS_ROOTFS) || \
	      true; \
	done
	[ -d $(BUILDDIR_INITRAMFS_ROOTFS)/lib ] || $(MKDIR) $(BUILDDIR_INITRAMFS_ROOTFS)/lib
	cd $(xm_boot_SYSROOT)/lib && $(CP) \
	  ld-*.so ld-*.so.* libc-*.so libc.so.*  libm-*.so libm.so.* \
	  libresolv-*.so libresolv.so.* libpthread-*.so libpthread.so.* \
	  $(BUILDDIR_INITRAMFS_ROOTFS)/lib
	cd $(linux_BUILDDIR) && $(linux_DIR)/usr/gen_initramfs.sh \
	  -o $(BUILDDIR_INITRAMFS)/initramfs.cpio \
	  $(BUILDDIR_INITRAMFS)/devlist $(BUILDDIR_INITRAMFS_ROOTFS)
	$(RM) $(BUILDDIR_INITRAMFS)/initramfs.cpio.gz
	gzip -9 -c $(BUILDDIR_INITRAMFS)/initramfs.cpio > \
	  $(BUILDDIR_INITRAMFS)/initramfs.cpio.gz

xm_boot_sd:
	[ -d /media/$(USER)/BOOT/boot ] || $(MKDIR) /media/$(USER)/BOOT/boot
	for i in $(DESTDIR_BOOT)/*; do \
	  if [ "`basename $$i`" = "u-boot.img" ]; then \
	    $(CP_V) $$i /media/$(USER)/BOOT/; \
	    continue; \
	  fi; \
	  if [ "`basename $$i`" = "MLO" ]; then \
	    $(CP_V) $$i /media/$(USER)/BOOT/; \
	    continue; \
	  fi; \
	  $(CP_V) $$i /media/$(USER)/BOOT/boot; \
	done

xm_boot: xm_boot_linux_LOADADDR?=0x81000000# 0x82000000
xm_boot: xm_boot_dtb_LOADADDR?=0x82000000# 0x83000000
xm_boot: xm_boot_initramfs_LOADADDR?=0x82100000# 0x83100000
xm_boot:
	@echo "... Manipulate utilities package"
	$(MAKE) $(addprefix $(@)_,tools)
	@echo "... Manipulate bootloader and kernel package"
	[ -d $(DESTDIR_BOOT) ] || $(MKDIR) $(DESTDIR_BOOT)
	$(CP) $(uboot_BUILDDIR)/MLO $(uboot_BUILDDIR)/u-boot.img \
	  $(DESTDIR_BOOT)/
	$(MAKE) LOADADDR=$(xm_boot_linux_LOADADDR) linux_uImage
	$(CP) $(linux_BUILDDIR)/arch/arm/boot/zImage \
	  $(linux_BUILDDIR)/arch/arm/boot/uImage \
	  $(linux_BUILDDIR)/arch/arm/boot/dts/omap3-beagle-xm-ab.dtb \
	  $(DESTDIR_BOOT)/
	$(MAKE) $(addprefix $(@)_,initramfs)
	$(CP) $(BUILDDIR_INITRAMFS)/initramfs.cpio.gz $(DESTDIR_BOOT)/
	mkimage -n 'bbq01 initramfs' -A arm -O linux -T ramdisk -C none \
	  -a $(xm_boot_initramfs_LOADADDR) -e $(xm_boot_initramfs_LOADADDR) \
	  -d $(BUILDDIR_INITRAMFS)/initramfs.cpio.gz $(DESTDIR_BOOT)/uInitramfs
	@echo "... Generate boot script"
	[ -d $(BUILDDIR) ] || $(MKDIR) $(BUILDDIR)
	@echo -n "" >  $(BUILDDIR)/xm_boot.sh
	@echo "setenv bootargs console=ttyS2,115200n8 root=/dev/ram0" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "setenv loadaddr $(xm_boot_linux_LOADADDR)" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "setenv fdtaddr $(xm_boot_dtb_LOADADDR)" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "setenv rdaddr $(xm_boot_initramfs_LOADADDR)" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "fatload mmc 0:1 \$${loadaddr} /boot/uImage" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "fatload mmc 0:1 \$${fdtaddr} /boot/omap3-beagle-xm-ab.dtb" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "setenv initrd_high 0xffffffff" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "fatload mmc 0:1 \$${rdaddr} /boot/uInitramfs" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "bootm \$${loadaddr} \$${rdaddr} \$${fdtaddr}" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	@echo "bootm \$${loadaddr} - \$${fdtaddr}" \
	  | tee -a $(BUILDDIR)/xm_boot.sh
	mkimage -n "boot script" -A arm -O linux -T script -C none \
	  -d $(BUILDDIR)/xm_boot.sh $(DESTDIR_BOOT)/boot.scr
	@echo "... Manipulate image tree"
	[ -d $(BUILDDIR) ] || $(MKDIR) $(BUILDDIR)
	sed -e "s/\$$ITS_KERNEL1_DATA/$(subst /,\/,$(linux_BUILDDIR)/arch/arm/boot/zImage)/" \
	  -e "s/\$$ITS_KERNEL1_LOADADDR/$(xm_boot_linux_LOADADDR)/" \
	  -e "s/\$$ITS_KERNEL1_ENTRYADDR/$(xm_boot_linux_LOADADDR)/" \
	  -e "s/\$$ITS_RAMDISK1_DATA/$(subst /,\/,$(BUILDDIR_INITRAMFS)/initramfs\.cpio\.gz)/" \
	  -e "s/\$$ITS_FDT1_DATA/$(subst /,\/,$(linux_BUILDDIR)/arch/arm/boot/dts/omap3-beagle-xm-ab\.dtb)/" \
	  < $(PROJDIR)/xm_its_template | tee $(BUILDDIR)/xm_cfg1.its
	mkimage -f $(BUILDDIR)/xm_cfg1.its $(DESTDIR_BOOT)/uImage.fit
	[ -d /media/joelai/BOOT ] && $(MAKE) xm_boot_sd \
	  && gio mount -e /media/joelai/BOOT || true

#------------------------------------
# dep: linux uboot busybox
#
xm_rootfs:
	[ -d $(BUILDDIR_ROOTFS) ] || $(MKDIR) $(BUILDDIR_ROOTFS)
	$(MAKE) linux_modules	
	$(MAKE) INSTALL_HDR_PATH=$(BUILDDIR_ROOTFS)/usr \
	  INSTALL_MOD_PATH=$(BUILDDIR_ROOTFS) \
	  linux_modules_install linux_headers_install
	[ -d $(linux_BUILDDIR)/Documentation/output ] && \
	  tar -Jcvf $(DESTDIR)/linux-docs.tar.xz --show-transformed-name \
	    --transform=s/output/linux-docs/ -C $(linux_BUILDDIR)/Documentation \
	    output
	[ -d $(uboot_BUILDDIR)/doc/output ] && \
	  tar -Jcvf $(DESTDIR)/uboot-docs.tar.xz --show-transformed-name \
	    --transform=s/output/uboot-docs/ -C $(uboot_BUILDDIR)/doc \
	    output
	[ -d $(busybox_BUILDDIR)/docs ] && \
	  tar -Jcvf $(DESTDIR)/busybox-docs.tar.xz --show-transformed-name \
	    --transform=s/docs/busybox-docs/ -C $(busybox_BUILDDIR) \
	    docs
	
#------------------------------------
#
	
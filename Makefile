#------------------------------------
#
PROJDIR?=$(abspath $(firstword $(wildcard ./builder ../builder))/..)
-include $(PROJDIR:%=%/)builder/site.mk
include $(PROJDIR:%=%/)builder/proj.mk

.DEFAULT_GOAL=help

APP_ATTR_xm?=xm
export APP_ATTR?=$(APP_ATTR_xm)

APP_PLATFORM=$(strip $(filter xm,$(APP_ATTR)))

ifneq ("$(strip $(filter xm,$(APP_ATTR)))","")
  TOOLCHAIN_PATH=$(HOME)/07_sw/gcc-arm-none-linux-gnueabihf
  CROSS_COMPILE=$(shell $(TOOLCHAIN_PATH)/bin/*-gcc -dumpmachine)-
  EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin)
  TOOLCHAIN_SYSROOT?=$(abspath $(shell PATH=$(call ENVPATH,$(EXTRA_PATH)) && \
    $(CC) -print-sysroot))
endif

export PATH:=$(call ENVPATH,$(PROJDIR)/tool/bin $(EXTRA_PATH))

$(info Makefile ... APP_ATTR: $(APP_ATTR), APP_PLATFORM: $(APP_PLATFORM), \
  TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT), PATH=$(PATH))

#------------------------------------
#
help:
	$(CC) -dumpmachine

#------------------------------------
# dep: apt install dvipng imagemagick
#
$(BUILDDIR)/pyenv:
	virtualenv -p python3 $(BUILDDIR)/pyenv
	@echo "Install package required for uboot, linux docs, etc."
	. $(BUILDDIR)/pyenv/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six

#------------------------------------
#
libc1_LIBS+=libm.so.* libm-*.so libresolv.so.* libresolv-*.so \
  libdl.so.* libdl-*.so libpthread.so.* libpthread-*.so \
  librt.so.* librt-*.so libc.so.* libc-*.so ld-*.so.* ld-*.so \
  libutil.so.* libutil-*.so

libc1_install: DESTDIR=$(BUILDDIR)/sysroot
libc1_install:
	[ -d $(DESTDIR)/lib ] || $(MKDIR) $(DESTDIR)/lib
	for i in $(sort $(libc1_LIBS)); do \
	  $(CP) $(TOOLCHAIN_SYSROOT)/lib/$$i $(DESTDIR)/lib/; \
	done

#------------------------------------
#
dtc_DIR?=$(HOME)/02_dev/dtc-v1.6.1+
dtc_BUILDDIR?=$(BUILDDIR)/dtc
dtc_MAKE=$(MAKE) PREFIX=$(PREFIX) -C $(dtc_BUILDDIR)
# dtc_MAKE+=V=1

$(dtc_BUILDDIR):
	git clone --depth=1 $(dtc_DIR) $@

dtc_distclean:
	$(RM) $(dtc_BUILDDIR)

dtc: $(dtc_BUILDDIR)
	$(dtc_MAKE)

dtc_install: PREFIX=$(PROJDIR)/tool

dtc_%: $(dtc_BUILDDIR)
	$(dtc_MAKE) $(@:dtc_%=%)

#------------------------------------
# ub_tools-only_defconfig ub_tools-only
#
ub_DIR?=$(HOME)/02_dev/u-boot-v2020.10+
ub_BUILDDIR?=$(BUILDDIR)/uboot
ub_DEF_MAKE=$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
  CONFIG_TOOLS_DEBUG=1
ub_MAKE=$(ub_DEF_MAKE) -C $(ub_BUILDDIR)

ub_mrproper:
	$(ub_DEF_MAKE) -C $(ub_DIR) $(@:ub_%=%)

APP_PLATFORM_ub_defconfig:
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(ub_BUILDDIR) && \
	  $(CP) $(DOTCFG) $(ub_BUILDDIR)/.config && \
	  $(ub_DEF_MAKE) O=$(ub_BUILDDIR) -C $(ub_DIR) oldconfig; \
	else \
	  $(ub_DEF_MAKE) O=$(ub_BUILDDIR) -C $(ub_DIR) $(DEFCFG); \
	fi

xm_ub_defconfig: DOTCFG=$(PROJDIR)/uboot_omap3_beagle.config
xm_ub_defconfig: DEFCFG=omap3_beagle_defconfig
xm_ub_defconfig: APP_PLATFORM_ub_defconfig

ub_defconfig $(ub_BUILDDIR)/.config:
	$(MAKE) ub_mrproper
	$(MAKE) $(APP_PLATFORM)_ub_defconfig

ub_distclean:
	$(RM) $(ub_BUILDDIR)

# dep: apt install dvipng imagemagick
#      apt install texlive-latex-extra
#      pip install sphinx_rtd_theme six
ub_htmldocs: | $(BUILDDIR)/pyenv $(ub_BUILDDIR)/.config
	# . $(BUILDDIR)/pyenv/bin/activate && \
	#   $(ub_MAKE) htmldocs
	tar -Jcvf $(BUILDDIR)/uboot-docs.tar.xz --show-transformed-names \
	  --transform="s/output/uboot-docs/" -C $(ub_BUILDDIR)/doc output

ub_tools_install: DESTDIR=$(PROJDIR)/tool
ub_tools_install: ub_tools
	[ -d $(DESTDIR)/bin ] || $(MKDIR) $(DESTDIR)/bin
	$(CP) $(ub_BUILDDIR)/tools/mkimage $(DESTDIR)/bin/

ub: $(ub_BUILDDIR)/.config
	$(ub_MAKE)

ub_%: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(@:ub_%=%)

#------------------------------------
#
linux_DIR?=$(HOME)/02_dev/linux-5.9+
linux_BUILDDIR?=$(BUILDDIR)/linux
linux_DEF_MAKE?=$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
  INSTALL_HDR_PATH=$(INSTALL_HDR_PATH) INSTALL_MOD_PATH=$(INSTALL_MOD_PATH) \
  LOADADDR=$(LOADADDR) CONFIG_INITRAMFS_SOURCE="$(CONFIG_INITRAMFS_SOURCE)"
#linux_DEF_MAKE+=V=1
linux_MAKE=$(linux_DEF_MAKE) -C $(linux_BUILDDIR)

linux_mrproper:
	$(linux_DEF_MAKE) -C $(linux_DIR) $(@:linux_%=%)

APP_PLATFORM_linux_defconfig:
	@echo "DOTCFG: $(DOTCFG), DEFCFG: $(DEFCFG)"
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(linux_BUILDDIR) && \
	  $(CP) $(DOTCFG) $(linux_BUILDDIR)/.config && \
	  $(linux_DEF_MAKE) O=$(linux_BUILDDIR) -C $(linux_DIR) oldconfig; \
	else \
	  $(linux_DEF_MAKE) O=$(linux_BUILDDIR) -C $(linux_DIR) $(DEFCFG); \
	fi

xm_linux_defconfig: DOTCFG=$(PROJDIR)/linux_omap2plus.config
xm_linux_defconfig: DEFCFG=omap2plus_defconfig # multi_v7_defconfig, omap2plus_defconfig
xm_linux_defconfig: APP_PLATFORM_linux_defconfig

linux_defconfig $(linux_BUILDDIR)/.config:
	$(MAKE) linux_mrproper
	$(MAKE) $(APP_PLATFORM)_linux_defconfig

linux_distclean:
	$(RM) $(linux_BUILDDIR)

# dep: apt install dvipng imagemagick
#      pip install sphinx_rtd_theme six
linux_htmldocs: | $(BUILDDIR)/pyenv $(linux_BUILDDIR)/.config
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(linux_MAKE) htmldocs
	tar -Jcvf $(BUILDDIR)/linux-docs.tar.xz \
	  --show-transformed-names \
	  --transform="s/output/linux-docs/" \
	  -C $(linux_BUILDDIR)/Documentation output

linux_modules_install: INSTALL_MOD_PATH=$(BUILDDIR)/sysroot
linux_headers_install: INSTALL_HDR_PATH=$(BUILDDIR)/sysroot

xm_linux_LOADADDR?=0x81000000

linux_uImage: LOADADDR?=$(APP_PLATFORM)_linux_LOADADDR

linux: $(linux_BUILDDIR)/.config
	$(linux_MAKE)

linux_%: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(@:linux_%=%)

#------------------------------------
#
bb_DIR?=$(HOME)/02_dev/busybox-1.9.2+
bb_BUILDDIR=$(BUILDDIR)/busybox
bb_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE)
bb_MAKE=$(bb_DEF_MAKE) CONFIG_PREFIX=$(CONFIG_PREFIX) -C $(bb_BUILDDIR)

bb_libc1_LIBS+=libm.so.* libm-*.so libresolv.so.* libresolv-*.so \
  libc.so.* libc-*.so
libc1_LIBS+=$(bb_libc1_LIBS)

bb_mrproper:
	$(bb_DEF_MAKE) -C $(bb_DIR) $(@:bb_%=%)

bb_defconfig $(bb_BUILDDIR)/.config:
	$(MAKE) bb_mrproper
	[ -d "$(bb_BUILDDIR)" ] || $(MKDIR) $(bb_BUILDDIR)
	if [ -f $(PROJDIR)/busybox.config ]; then \
	  $(CP) $(PROJDIR)/busybox.config $(bb_BUILDDIR)/.config && \
	  $(bb_DEF_MAKE) O=$(bb_BUILDDIR) -C $(bb_DIR) oldconfig; \
	else \
	  $(bb_DEF_MAKE) O=$(bb_BUILDDIR) -C $(bb_DIR) defconfig; \
	fi

bb_distclean:
	$(RM) $(bb_BUILDDIR)

# dep: apt install docbook
bb_doc: | $(bb_BUILDDIR)/.config
	$(bb_MAKE) doc
	tar -Jcvf $(BUILDDIR)/busybox-docs.tar.xz \
	  --show-transformed-names \
	  --transform="s/docs/busybox-docs/" \
	  -C $(bb_BUILDDIR) docs

bb_install: CONFIG_PREFIX=$(BUILDDIR)/sysroot

bb: $(bb_BUILDDIR)/.config
	$(bb_MAKE)

bb_%: $(bb_BUILDDIR)/.config
	$(bb_MAKE) $(@:bb_%=%)

#------------------------------------
#
libasound_DIR=$(PROJDIR)/package/alsa-lib-1.2.5.1
libasound_BUILDDIR=$(BUILDDIR)/alsa-lib
libasound_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(libasound_BUILDDIR)

libasound_libc1_LIBS+=libm.so.* libm-*.so libdl.so.* libdl-*.so \
  libpthread.so.* libpthread-*.so librt.so.* librt-*.so \
  libc.so.* libc-*.so ld-*.so.* ld-*.so
libc1_LIBS+=$(libasound_libc1_LIBS)

libasound_configure $(libasound_BUILDDIR)/Makefile:
	[ -d "$(libasound_BUILDDIR)" ] || $(MKDIR) $(libasound_BUILDDIR)
	cd $(libasound_BUILDDIR) && \
	  $(libasound_DIR)/configure --host=`$(CC) -dumpmachine` --prefix= \
	    --disable-topology

libasound_install: DESTDIR=$(BUILDDIR)/sysroot

libasound: $(libasound_BUILDDIR)/Makefile
	$(libasound_MAKE)

libasound_%: $(libasound_BUILDDIR)/Makefile
	$(libasound_MAKE) $(@:libasound_%=%)

#------------------------------------
#
zlib_DIR=$(PROJDIR)/package/zlib
zlib_BUILDDIR=$(BUILDDIR)/zlib
zlib_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(zlib_BUILDDIR)

zlib_configure $(zlib_BUILDDIR)/configure.log:
	[ -d "$(zlib_BUILDDIR)" ] || \
	  git clone --depth=1 $(zlib_DIR) $(zlib_BUILDDIR)
	cd $(zlib_BUILDDIR) && \
	  prefix= CROSS_PREFIX=$(CROSS_COMPILE) CFLAGS="-fPIC" ./configure

zlib_distclean:
	$(RM) $(zlib_BUILDDIR)

zlib_install: DESTDIR=$(BUILDDIR)/sysroot

zlib: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE)

zlib_%: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE) $(patsubst _%,%,$(@:zlib%=%))

#------------------------------------
#
ncursesw_DIR=$(PROJDIR)/package/ncurses-6.2
ncursesw_BUILDDIR=$(BUILDDIR)/ncursesw
ncursesw_TINFODIR=/usr/share/terminfo
ncursesw_TINFO=ansi,ansi-m,color_xterm,linux,pcansi-m,rxvt-basic,vt52,vt100,vt102,vt220,xterm,tmux-256color
ncursesw_DEF_CFG=$(ncursesw_DIR)/configure --prefix= --with-shared \
  --with-termlib --with-ticlib --enable-widec --disable-db-install
ncursesw_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(ncursesw_BUILDDIR)

ncursesw_host_install: DESTDIR=$(PROJDIR)/tool
ncursesw_host_install: ncursesw_BUILDDIR=$(BUILDDIR)/ncursesw/host
ncursesw_host_install:
	[ -d "$(ncursesw_BUILDDIR)" ] || $(MKDIR) $(ncursesw_BUILDDIR)
	cd $(ncursesw_BUILDDIR) && $(ncursesw_DEF_CFG)
	$(ncursesw_MAKE) install
	echo "INPUT(-lncursesw)" > $(DESTDIR)/lib/libncurses.so
	echo "INPUT(-ltinfow)" > $(DESTDIR)/lib/libtinfo.so

ncursesw_configure $(ncursesw_BUILDDIR)/Makefile:
	# [ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_install
	[ -d "$(ncursesw_BUILDDIR)" ] || $(MKDIR) $(ncursesw_BUILDDIR)
	cd $(ncursesw_BUILDDIR) && \
	  $(ncursesw_DEF_CFG) --host=`$(CC) -dumpmachine` \
	  --with-default-terminfo-dir=$(ncursesw_TINFODIR) \
	  --without-tests --disable-stripping --without-manpages

ncursesw_distclean:
	$(RM) $(ncursesw_BUILDDIR)

ncursesw_install: DESTDIR=$(BUILDDIR)/sysroot
ncursesw_install: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE) install
	if [ -x $(PROJDIR)/tool/bin/tic ]; then \
	  ( [ -d "$(DESTDIR)/$(ncursesw_TINFODIR)" ] || \
	    $(MKDIR) $(DESTDIR)/$(ncursesw_TINFODIR) ) && \
	  LD_LIBRARY_PATH=$(PROJDIR)/tool/lib tic -s -1 -I -e'$(ncursesw_TINFO)' \
	    $(ncursesw_DIR)/misc/terminfo.src > $(BUILDDIR)/terminfo.src; \
	  LD_LIBRARY_PATH=$(PROJDIR)/tool/lib tic -s -o $(ncursesw_TINFODIR) \
	    $(BUILDDIR)/terminfo.src; \
	fi
	echo "INPUT(-lncursesw)" > $(DESTDIR)/lib/libncurses.so
	echo "INPUT(-ltinfow)" > $(DESTDIR)/lib/libtinfo.so

ncursesw: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE)

ncursesw_%: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE) $(@:ncursesw_%=%)

#------------------------------------
# dep: make libasound_install ncursesw_install
#
alsautil_DIR=$(PROJDIR)/package/alsa-utils-1.2.5.1
alsautil_BUILDDIR=$(BUILDDIR)/alsa-utils
alsautil_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(alsautil_BUILDDIR)
alsautil_INCDIR=$(BUILDDIR)/sysroot/include $(BUILDDIR)/sysroot/include/ncursesw
alsautil_LIBDIR=$(BUILDDIR)/sysroot/lib
alsautil_DEP=libasound ncursesw

alsautil_configure $(alsautil_BUILDDIR)/Makefile:
	[ -d "$(alsautil_BUILDDIR)" ] || $(MKDIR) $(alsautil_BUILDDIR)
	cd $(alsautil_BUILDDIR) && \
	  CPPFLAGS="$(addprefix -I,$(alsautil_INCDIR))" \
	  LDFLAGS="$(addprefix -L,$(alsautil_LIBDIR))" \
	  $(alsautil_DIR)/configure --host=`$(CC) -dumpmachine` --prefix= \
	    --disable-alsatest

alsautil_install: DESTDIR=$(BUILDDIR)/sysroot

alsautil: $(alsautil_BUILDDIR)/Makefile
	$(alsautil_MAKE)

alsautil_%: $(alsautil_BUILDDIR)/Makefile
	$(alsautil_MAKE) $(@:alsautil_%=%)

#------------------------------------
#
sdl_DIR=$(PROJDIR)/package/SDL2-2.0.14
sdl_BUILDDIR=$(BUILDDIR)/sdl
sdl_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(sdl_BUILDDIR)

sdl_configure:
	[ -d "$(sdl_BUILDDIR)" ] || $(MKDIR) $(sdl_BUILDDIR)
	cd $(sdl_BUILDDIR) && \
	  $(sdl_DIR)/configure --host=`$(CC) -dumpmachine` --prefix=

sdl_install: DESTDIR=$(BUILDDIR)/sysroot

sdl: $(sdl_BUILDDIR)/Makefile
	$(sdl_MAKE)

sdl_%: $(sdl_BUILDDIR)/Makefile
	$(sdl_MAKE) $(@:sdl_%=%)

#------------------------------------
# dep: zlib libasound_install ncursesw_install
#
ff_DIR=$(PROJDIR)/package/ffmpeg
ff_BUILDDIR=$(BUILDDIR)/ffmpeg
ff_INCDIR=$(BUILDDIR)/sysroot/include $(BUILDDIR)/sysroot/include/ncursesw \
  $(BUILDDIR)/sysroot/include/SDL2
ff_LIBDIR=$(BUILDDIR)/sysroot/lib
ff_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(ff_BUILDDIR)
ff_DEP=zlib libasound ncursesw

ff_configure $(ff_BUILDDIR)/Makefile:
	[ -d "$(ff_BUILDDIR)" ] || $(MKDIR) $(ff_BUILDDIR)
	cd $(ff_BUILDDIR) && \
	  $(ff_DIR)/configure --enable-cross-compile --target-os=linux \
	    --cross_prefix=$(CROSS_COMPILE) --prefix=/ --arch=arm --cpu=cortex-a5 \
		--disable-iconv \
	    --enable-vfpv3 --enable-pic --enable-shared \
	    --enable-hardcoded-tables --enable-pthreads \
		--enable-ffplay \
	    --extra-cflags="$(addprefix -I,$(ff_INCDIR)) -D_REENTRANT" \
	    --extra-ldflags="$(addprefix -L,$(ff_LIBDIR))"

ff_install: DESTDIR=$(BUILDDIR)/sysroot

ff: $(ff_BUILDDIR)/Makefile
	$(ff_MAKE)

ff_%: $(ff_BUILDDIR)/Makefile
	$(ff_MAKE) $(@:ff_%=%)

#------------------------------------
# dep: ub ub_tools linux_bzImage linux_dtbs bb dtc
#
dist_DIR?=$(DESTDIR)

# reference from linux_dtbs
dist_DTINCDIR+=$(linux_DIR)/scripts/dtc/include-prefixes \
  $(linux_DIR)/arch/arm/boot/dts

xm_dist: xm_dist_dts=$(PROJDIR)/omap3-beagle-xm-ab.dts
xm_dist: xm_dist_dtb=$(linux_BUILDDIR)/arch/arm/boot/dts/omap3-beagle-xm-ab.dtb
xm_dist: xm_dist_linux_LOADADDR?=0x81000000# 0x82000000
xm_dist: xm_dist_dtb_LOADADDR?=0x82000000# 0x83000000
xm_dist: xm_dist_initramfs_LOADADDR?=0x82100000# 0x83100000
xm_dist:
	$(MAKE) ub linux_bzImage linux_dtbs
	$(MAKE) bb_install libc1_install
	[ -d $(dist_DIR)/boot ] || $(MKDIR) $(dist_DIR)/boot
	$(CP) $(ub_BUILDDIR)/MLO $(ub_BUILDDIR)/u-boot.img \
	  $(linux_BUILDDIR)/arch/arm/boot/zImage $(xm_dist_dtb) \
	  $(linux_BUILDDIR)/arch/arm/boot/dts/omap3-beagle-xm.dtb \
	  $(dist_DIR)/boot/
	[ -f "$($(APP_PLATFORM)_dist_dts)" ] && \
	  $(call CPPDTS) $(addprefix -I,$(dist_DTINCDIR)) \
	    -o $(BUILDDIR)/$(notdir $($(APP_PLATFORM)_dist_dts)) \
	    $($(APP_PLATFORM)_dist_dts) && \
	  $(call DTC2) $(addprefix -i,$(dist_DTINCDIR)) \
	    -o $(dist_DIR)/boot/$(basename $(notdir $($(APP_PLATFORM)_dist_dts))).dtb \
	    $(BUILDDIR)/$(notdir $($(APP_PLATFORM)_dist_dts))
	# cat <<-EOFF > $(PROJDIR)/build/abc
	#   setenv bootargs console=ttyS2,115200n8 root=/dev/mmcblk0p2 rw rootwait \
	#   setenv loadaddr 0x81000000; setenv fdtaddr 0x82000000 \
	#   fatload mmc 0:1 ${loadaddr} /zImage; fatload mmc 0:1 ${fdtaddr} /omap3-beagle-xm-ab.dtb; bootz ${loadaddr} - ${fdtaddr} \
	# EOFF

xm_dist_sd:
	$(CP) $(dist_DIR)/boot/* /media/$(USER)/BOOT/
	$(CP) $(BUILDDIR)/sysroot/* /media/$(USER)/rootfs/

xm_boot_tools:
	[ -d $(PROJDIR)/tool/bin ] || $(MKDIR) $(PROJDIR)/tool/bin
	$(CP) $(ub_BUILDDIR)/tools/mkimage $(PROJDIR)/tool/bin/
	$(dtc_MAKE) DESTDIR= PREFIX=$(PROJDIR)/tool install

xm_boot_initramfs: xm_boot_SYSROOT?=$(shell $(CC) -print-sysroot)
xm_boot_initramfs:
	[ -d "$(BUILDDIR_INITRAMFS_ROOTFS)" ] || $(MKDIR) $(BUILDDIR_INITRAMFS_ROOTFS)
	echo -n "" > $(BUILDDIR_INITRAMFS)/devlist
	echo "dir /dev 0755 0 0" >> $(BUILDDIR_INITRAMFS)/devlist
	echo "nod /dev/console 0600 0 0 c 5 1" >> $(BUILDDIR_INITRAMFS)/devlist
	$(bb_MAKE) CONFIG_PREFIX=$(BUILDDIR_INITRAMFS_ROOTFS) \
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
	[ -d "$(DESTDIR_BOOT)" ] || $(MKDIR) $(DESTDIR_BOOT)
	$(CP) $(ub_BUILDDIR)/MLO $(ub_BUILDDIR)/u-boot.img \
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
	[ -d "$(BUILDDIR)" ] || $(MKDIR) $(BUILDDIR)
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
	[ -d "$(BUILDDIR)" ] || $(MKDIR) $(BUILDDIR)
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
# dep: linux ub bb
#
xm_rootfs:
	[ -d "$(BUILDDIR_ROOTFS)" ] || $(MKDIR) $(BUILDDIR_ROOTFS)
	$(MAKE) linux_modules	
	$(MAKE) INSTALL_HDR_PATH=$(BUILDDIR_ROOTFS)/usr \
	  INSTALL_MOD_PATH=$(BUILDDIR_ROOTFS) \
	  linux_modules_install linux_headers_install
	[ -d $(linux_BUILDDIR)/Documentation/output ] && \
	  tar -Jcvf $(DESTDIR)/linux-docs.tar.xz --show-transformed-name \
	    --transform=s/output/linux-docs/ -C $(linux_BUILDDIR)/Documentation \
	    output
	[ -d $(ub_BUILDDIR)/doc/output ] && \
	  tar -Jcvf $(DESTDIR)/uboot-docs.tar.xz --show-transformed-name \
	    --transform=s/output/uboot-docs/ -C $(ub_BUILDDIR)/doc \
	    output
	[ -d $(bb_BUILDDIR)/docs ] && \
	  tar -Jcvf $(DESTDIR)/busybox-docs.tar.xz --show-transformed-name \
	    --transform=s/docs/busybox-docs/ -C $(bb_BUILDDIR) \
	    docs
	
#------------------------------------
#
	
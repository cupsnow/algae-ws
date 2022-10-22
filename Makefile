#!/usr/bin/env -S make -s
#------------------------------------
#
PROJDIR?=$(abspath $(firstword $(wildcard ./builder ../builder))/..)
-include $(PROJDIR:%=%/)builder/site.mk
include $(PROJDIR:%=%/)builder/proj.mk

.DEFAULT_GOAL=help
SHELL=/bin/bash

BUILDPARALLEL?=$(shell SYSCPUS=$$(nproc) \
    && [ $${SYSCPUS} -ge 4 ] \
    && echo $$(( $${SYSCPUS} / 2 )) \
    || echo 1)

BUILDDIR2=$(abspath $(PROJDIR)/../build)
PKGDIR2=$(abspath $(PROJDIR)/..)

# build_host_nonroot
ifneq ($(strip $(shell type -P raspi-config)),)
APP_ATTR_BUILD_HOST=build_host_rpi build_host_rpi3b
else ifeq ($(strip $(LSBID)),ubuntu)
APP_ATTR_BUILD_HOST=build_host_ub20
endif

# ath9k_htc
APP_ATTR_xm?=xm ath9k_htc
APP_ATTR_bpi?=bpi ath9k_htc
APP_ATTR_ub20?=ub20
export APP_ATTR?=$(APP_ATTR_bpi) $(APP_ATTR_BUILD_HOST)

APP_PLATFORM=$(strip $(filter xm bpi ub20,$(APP_ATTR)))

ifneq ($(strip $(filter xm,$(APP_PLATFORM))),)
APP_BUILD=arm
else ifneq ($(strip $(filter bpi,$(APP_PLATFORM))),)
APP_BUILD=aarch64
else
APP_BUILD=$(APP_PLATFORM)
endif

ifneq ($(strip $(filter xm,$(APP_ATTR))),)
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/gcc-arm-none-linux-gnueabihf))
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin)
else ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/gcc-aarch64-none-linux-gnu))
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/or1k-linux-musl,OR1K))
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin) $(OR1K_TOOLCHAIN_PATH:%=%/bin)
else ifneq ($(strip $(filter ub20,$(APP_PLATFORM))),)
TOOLCHAIN_SYSROOT=$(abspath $(shell gcc -print-sysroot))
TOOLCHAIN_TARGET=$(shell gcc -dumpmachine)
CROSS_COMPILE=$(TOOLCHAIN_TARGET)-
endif

export PATH:=$(call ENVPATH,$(PROJDIR)/tool/bin $(EXTRA_PATH) $(PATH))
# export LD_LIBRARY_PATH:=$(call ENVPATH,$(PROJDIR)/tool/lib $(LD_LIBRARY_PATH))

BUILD_SYSROOT?=$(BUILDDIR2)/sysroot-$(APP_PLATFORM)

# $(BUILD_PKGCFG_ENV) pkg-config --list-all
BUILD_PKGCFG_ENV+=PKG_CONFIG_LIBDIR="$(BUILD_SYSROOT)/lib/pkgconfig" \
    PKG_CONFIG_SYSROOT_DIR="$(BUILD_SYSROOT)"

ifneq ("$(wildcard $(PROJDIR)/tool/bin/tic)","")
BUILD_TINFO_ENV+=TERMINFO=$(PROJDIR)/tool/$(ncursesw_TINFODIR)
endif

ifneq ($(strip $(filter som1 wlsom1 sa7715,$(APP_PLATFORM))),)
BUILD_CFLAGS_$(APP_PLATFORM)+=-march=armv7-a -mfloat-abi=hard
BUILD_CFLAGS2_$(APP_PLATFORM)+=$(BUILD_CFLAGS_$(APP_PLATFORM)) -mfpu=vfpv4
endif

# $(info Makefile ... Variable summary:$(NEWLINE) \
#     $(EMPTY) APP_ATTR: $(APP_ATTR), APP_PLATFORM: $(APP_PLATFORM)$(NEWLINE) \
#     $(EMPTY) TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT)$(NEWLINE) \
#     $(EMPTY) OR1K_TOOLCHAIN_SYSROOT: $(OR1K_TOOLCHAIN_SYSROOT)$(NEWLINE) \
#     $(EMPTY) PATH=$(PATH))

#------------------------------------
#
help:
	@$(ANSI_COLOR_DEMO)
	@echo "APP_ATTR: $(APP_ATTR)"
	@echo "TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT)"
	@echo "TOOLCHAIN_PATH: $(TOOLCHAIN_PATH)"
ifneq ($(strip $(V)),)
	$(BUILD_PKGCFG_ENV) pkg-config --list-all
endif

FORCE:# keep empty
# keep empty

#------------------------------------
# dep: apt install dvipng imagemagick plantuml
#
pyvenv pyenv $(BUILDDIR)/pyenv:
	virtualenv -p python3.9 $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  python --version && \
	  pip install -r requirements.txt

pyvenv2 pyenv2 $(BUILDDIR)/pyenv2:
	virtualenv -p python2 $(BUILDDIR)/pyenv2
	. $(BUILDDIR)/pyenv2/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six

#------------------------------------
# Device Tree Compiler v1.1-487-g6c02224
#
dtc_MAKEPARAM_$(APP_PLATFORM)=CC=$(CC) PREFIX= DESTDIR=$(DESTDIR) NO_PYTHON=1

$(eval $(call AC_BUILD3_HEAD,dtc $(PKGDIR2)/dtc $(BUILDDIR2)/dtc-$(APP_BUILD)))

dtc_PKG=$(dir $(dtc_BUILDDIR))/dtc-pkg.tar

dtc_pkg $(dtc_PKG):
	$(call GIT_ARCHIVE,$(dtc_PKG),$(dtc_DIR))

dtc_defconfig $(dtc_BUILDDIR)/Makefile: | $(dtc_PKG)
	# git clone $(dtc_DIR) $(dtc_BUILDDIR)
	[ -d $(dtc_BUILDDIR) ] || $(MKDIR) $(dtc_BUILDDIR)
	tar -xvf $(dtc_PKG) -C $(dtc_BUILDDIR) --strip-components=1

dtc_footprint $(dtc_BUILDDIR)_footprint:
	[ -d $(dir $(dtc_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(dtc_BUILDDIR)_footprint)
	echo "NO_PYTHON=1" > $(dtc_BUILDDIR)_footprint

dtc_host_install $(PROJDIR)/tool/bin/dtc:
	$(MAKE) APP_ATTR=ub20 DESTDIR=$(PROJDIR)/tool dtc_install

$(eval $(call AC_BUILD3_DISTCLEAN,dtc))
$(eval $(call AC_BUILD3_DIST_INSTALL,dtc))
$(eval $(call AC_BUILD3_FOOT,dtc))

#------------------------------------
# sunxi-tools v1.1-487-g6c02224
# man $(sunxitools_BUILDDIR)/sunxi-fel.1
# dep: dtc_host_install
#
sunxitools_DIR=$(PKGDIR2)/sunxi-tools
sunxitools_BUILDDIR=$(BUILDDIR)/sunxitools-host
sunxitools_PKGDEP=dtc_host
sunxitools_CFLAGS=-I$(PROJDIR)/tool/include -L$(PROJDIR)/tool/lib
sunxitools_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) \
    CFLAGS="$(sunxitools_CFLAGS)" DESTDIR=$(DESTDIR) PREFIX= \
    -C $(sunxitools_BUILDDIR)

sunxitools_defconfig $(sunxitools_BUILDDIR)/Makefile:
	[ -d "$(sunxitools_BUILDDIR)" ] || $(MKDIR) $(sunxitools_BUILDDIR)
	cd $(sunxitools_DIR) && tar -cvf - --exclude=".git" --exclude=".github" * \
	  | tar -xvf - -C $(sunxitools_BUILDDIR)

sunxitools_install: DESTDIR=$(PROJDIR)/tool

sunxitools: $(sunxitools_BUILDDIR)/Makefile | $(PROJDIR)/tool/bin/dtc
	$(sunxitools_MAKE) $(BUILDPARALLEL:%=-j%)

sunxitools_%: $(sunxitools_BUILDDIR)/Makefile | $(PROJDIR)/tool/bin/dtc
	$(sunxitools_MAKE) $(BUILDPARALLEL:%=-j%) $(@:sunxitools_%=%)

#------------------------------------
# ARM Trusted Firmware-A v2.5-294-gabde216dc
#
atf_DIR?=$(PKGDIR2)/atf
atf_BUILDDIR?=$(BUILDDIR2)/atf-$(APP_PLATFORM)
atf_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) DEBUG=1 \
    BUILD_BASE=$(atf_BUILDDIR)
ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
atf_DEF_MAKE+=ARCH=aarch64 PLAT=sun50i_a64
else
atf_DEF_MAKE=@echo "Unknown platform for ATF" && false
endif
atf_MAKE=$(atf_DEF_MAKE) -C $(atf_DIR)

# dep: apt install plantuml
#      pip install sphinxcontrib-plantuml
atf_doc: | $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  BUILDDIR=$(atf_BUILDDIR)/doc $(atf_MAKE) doc
	tar -Jcvf $(BUILDDIR)/atf-docs.tar.xz --show-transformed-names \
	    --transform="s/html/atf-docs/" \
	    -C $(atf_BUILDDIR)/package/atf/docs/build html

ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
atf: atf_bl31
endif

atf_%:
	$(atf_MAKE) $(BUILDPARALLEL:%=-j%) $(@:atf_%=%)

#------------------------------------
# Crust: Libre SCP firmware for Allwinner sunxi SoCs v0.4-5-gcff057d
#
crust_DIR?=$(PKGDIR2)/crust
crust_BUILDDIR?=$(BUILDDIR2)/crust-$(APP_PLATFORM)
crust_MAKE=$(MAKE) OBJ=$(crust_BUILDDIR) SRC=$(crust_DIR) \
    CROSS_COMPILE=$(OR1K_CROSS_COMPILE) -f $(crust_DIR)/Makefile \
    -C $(crust_BUILDDIR)

crust_defconfig $(crust_BUILDDIR)/.config:
	[ -d "$(crust_BUILDDIR)" ] || $(MKDIR) $(crust_BUILDDIR)
	$(crust_MAKE) pine64_plus_defconfig

$(addprefix crust_,clean distclean docs):
	$(crust_MAKE) $(@:crust_%=%)

ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
crust: crust_scp
endif

crust_%: $(crust_BUILDDIR)/.config
	$(crust_MAKE) $(BUILDPARALLEL:%=-j%) $(@:crust_%=%)

#------------------------------------
# u-boot v2021.10-rc1-269-g8f07f5376a
# ub_tools-only_defconfig ub_tools-only
# dep for bpi: atf_bl31, crust_scp
#
ub_DIR?=$(PKGDIR2)/uboot
ub_BUILDDIR?=$(BUILDDIR)/uboot-$(APP_PLATFORM)
ub_PKGDEP=atf_bl31 crust_scp
ub_DEF_MAKE?=$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
    KBUILD_OUTPUT=$(ub_BUILDDIR) CONFIG_TOOLS_DEBUG=1
ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
ub_DEF_MAKE+=BL31=$(atf_BUILDDIR)/sun50i_a64/debug/bl31.bin \
    SCP=$(or $(wildcard $(crust_BUILDDIR)/scp/scp.bin),/dev/null)
endif
ub_MAKE=$(ub_DEF_MAKE) -C $(ub_BUILDDIR)

ub_mrproper ub_help:
	$(ub_DEF_MAKE) -C $(ub_DIR) $(@:ub_%=%)

# failed to build out-of-tree as of -f for linux
APP_PLATFORM_ub_defconfig:
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(ub_BUILDDIR) && \
	  $(CP) $(DOTCFG) $(ub_BUILDDIR)/.config && \
	  yes "" | $(ub_DEF_MAKE) -C $(ub_DIR) oldconfig; \
	else \
	  $(ub_DEF_MAKE) -C $(ub_DIR) $(DEFCFG); \
	fi

bpi_ub_defconfig: DOTCFG=$(PROJDIR)/bananapi_m64_defconfig
bpi_ub_defconfig: DEFCFG=bananapi_m64_defconfig
bpi_ub_defconfig: APP_PLATFORM_ub_defconfig

xm_ub_defconfig: DOTCFG=$(PROJDIR)/uboot_omap3_beagle.config
xm_ub_defconfig: DEFCFG=omap3_beagle_defconfig
xm_ub_defconfig: APP_PLATFORM_ub_defconfig

ub_defconfig $(ub_BUILDDIR)/.config:
	$(MAKE) ub_mrproper
	$(MAKE) $(APP_PLATFORM)_ub_defconfig

ub_distclean:
	$(RM) $(ub_BUILDDIR)

# dep: apt install dvipng imagemagick texlive-latex-extra
#      pip install sphinx_rtd_theme six
ub_htmldocs: | $(BUILDDIR)/pyenv $(ub_BUILDDIR)/.config
ifeq ("$(NB)","")
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(ub_MAKE) htmldocs
endif
	tar -Jcvf $(BUILDDIR)/uboot-docs.tar.xz --show-transformed-names \
	  --transform="s/output/uboot-docs/" -C $(ub_BUILDDIR)/doc \
	  output

ub_tools_install: DESTDIR=$(PROJDIR)/tool
ub_tools_install: ub_tools
	[ -d $(DESTDIR)/bin ] || $(MKDIR) $(DESTDIR)/bin
	cd $(ub_BUILDDIR)/tools && \
	  rsync -avR --info=progress2 \
	    dumpimage fdtgrep gen_eth_addr gen_ethaddr_crc mkenvimage mkimage \
		proftool spl_size_limit \
		$(DESTDIR)/bin/

ub_envtools: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(BUILDPARALLEL:%=-j%) cmd_crosstools_strip="true skip strip" \
	    $(@:ub_%=%)

ub_envtools_install: DESTDIR=$(BUILD_SYSROOT)
ub_envtools_install: ub_envtools
	[ -d $(DESTDIR)/sbin ] || $(MKDIR) $(DESTDIR)/sbin
	$(CP) $(ub_BUILDDIR)/tools/env/fw_printenv $(DESTDIR)/sbin/
	ln -sf fw_printenv $(DESTDIR)/sbin/fw_setenv

ub: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(BUILDPARALLEL:%=-j%)

ub_%: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(BUILDPARALLEL:%=-j%) $(@:ub_%=%)

#------------------------------------
# Linux kernel v5.14-rc7-89-g77dd11439b86
#
linux_DIR?=$(PKGDIR2)/linux
linux_BUILDDIR?=$(BUILDDIR2)/linux-$(APP_PLATFORM)
linux_DEF_MAKE1?=$(MAKE) $(linux_DEF_MAKEPARAM1_$(APP_PLATFORM)) \
    CROSS_COMPILE=$(CROSS_COMPILE)
linux_DEF_MAKE?=$(linux_DEF_MAKE1) $(linux_DEF_MAKEPARAM_$(APP_PLATFORM)) \
    O=$(linux_BUILDDIR) \
    INSTALL_HDR_PATH=$(or $(INSTALL_HDR_PATH),$(DESTDIR)) \
	INSTALL_MOD_PATH=$(or $(INSTALL_MOD_PATH),$(DESTDIR)) \
	LOADADDR=$(LOADADDR) CONFIG_INITRAMFS_SOURCE="$(CONFIG_INITRAMFS_SOURCE)"

linux_DEF_MAKEPARAM1_bpi+=ARCH=arm64
linux_DEF_MAKEPARAM1_xm+=ARCH=arm

linux_MAKE=$(linux_DEF_MAKE) $(linux_MAKEPARAM_$(APP_PLATFORM)) -C $(linux_BUILDDIR)
linux_kernelrelease=$(shell PATH=$(PATH) $(linux_MAKE) -s kernelrelease)

linux_mrproper linux_help:
	$(linux_DEF_MAKE1) -C $(linux_DIR) $(@:linux_%=%)

APP_PLATFORM_linux_defconfig:
	$(MAKE) linux_mrproper
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(linux_BUILDDIR) && \
	  $(CP) $(DOTCFG) $(linux_BUILDDIR)/.config && \
	  { yes "" | $(linux_MAKE) -f $(linux_DIR)/Makefile oldconfig; }; \
	else \
	  $(linux_MAKE) -f $(linux_DIR)/Makefile $(DEFCFG); \
	fi

bpi_linux_defconfig: DOTCFG=$(PROJDIR)/linux_bpi.config
bpi_linux_defconfig: DEFCFG=defconfig
bpi_linux_defconfig: APP_PLATFORM_linux_defconfig

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
ifeq ("$(NB)","")
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(linux_MAKE) htmldocs
endif
	tar -Jcvf $(BUILDDIR)/linux-docs.tar.xz --show-transformed-names \
	  --transform="s/output/linux-docs/" -C $(linux_BUILDDIR)/Documentation \
	  output

linux_modules_install: INSTALL_MOD_PATH=$(BUILD_SYSROOT)

linux_headers_install: INSTALL_HDR_PATH=$(BUILD_SYSROOT)

bpi_linux_LOADADDR?=0x40200000

xm_linux_LOADADDR?=0x81000000

linux_uImage: LOADADDR?=$(APP_PLATFORM)_linux_LOADADDR

kernelrelease=$(BUILDDIR)/kernelrelease-$(APP_PLATFORM)
linux_kernelrelease $(kernelrelease):
	[ -d $(dir $(kernelrelease)) ] || $(MKDIR) $(dir $(kernelrelease))
	"make" -s --no-print-directory linux_kernelrelease > $(kernelrelease)

linux: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(BUILDPARALLEL:%=-j%)

linux_%: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(BUILDPARALLEL:%=-j%) $(@:linux_%=%)

#------------------------------------
# busybox 1_12_0-7872-g8ae6a4344
#
bb_DIR=$(PKGDIR2)/busybox
bb_BUILDDIR?=$(BUILDDIR2)/busybox-$(APP_BUILD)
bb_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE)
bb_MAKE=$(bb_DEF_MAKE) CONFIG_PREFIX=$(or $(CONFIG_PREFIX),$(DESTDIR)) \
    -C $(bb_BUILDDIR)

bb_mrproper:
	$(bb_DEF_MAKE) -C $(bb_DIR) $(@:bb_%=%)

APP_PLATFORM_bb_defconfig:
	$(MAKE) bb_mrproper
	[ -d "$(bb_BUILDDIR)" ] || $(MKDIR) $(bb_BUILDDIR)
	if [ -f "$(DOTCFG)" ]; then \
	  $(CP) $(DOTCFG) $(bb_BUILDDIR)/.config && \
	  yes "" | $(bb_DEF_MAKE) O=$(bb_BUILDDIR) -C $(bb_DIR) oldconfig; \
	else \
	  yes "" | $(bb_DEF_MAKE) O=$(bb_BUILDDIR) -C $(bb_DIR) defconfig; \
	fi

ifneq ($(strip $(filter ub20,$(APP_ATTR))),)
$(APP_PLATFORM)_bb_defconfig: DOTCFG=$(PROJDIR)/busybox_ub20.config
else
$(APP_PLATFORM)_bb_defconfig: DOTCFG=$(PROJDIR)/busybox.config
endif
$(APP_PLATFORM)_bb_defconfig: APP_PLATFORM_bb_defconfig

bb_defconfig $(bb_BUILDDIR)/.config:
	$(MAKE) bb_mrproper
	$(MAKE) $(APP_PLATFORM)_bb_defconfig

bb_distclean:
	$(RM) $(bb_BUILDDIR)

# dep: apt install docbook
bb_doc: | $(bb_BUILDDIR)/.config
	$(bb_MAKE) doc
	tar -Jcvf $(BUILDDIR)/busybox-docs.tar.xz --show-transformed-names \
	  --transform="s/docs/busybox-docs/" \
	  -C $(bb_BUILDDIR) docs

bb_install: DESTDIR=$(BUILD_SYSROOT)

bb_dist_install: DESTDIR=$(BUILD_SYSROOT)
bb_dist_install:
	$(RM) $(bb_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,bb,$(bb_BUILDDIR)/.config $(PROJDIR)/busybox.config)

bb: $(bb_BUILDDIR)/.config
	$(bb_MAKE) $(BUILDPARALLEL:%=-j%)

bb_%: $(bb_BUILDDIR)/.config
	$(bb_MAKE) $(BUILDPARALLEL:%=-j%) $(@:bb_%=%)

#------------------------------------
#
cryptodev_DIR=$(PKGDIR2)/cryptodev-linux
cryptodev_BUILDDIR?=$(BUILDDIR2)/cryptodev-$(APP_BUILD)
cryptodev_MAKE=$(linux_MAKE) M=$(cryptodev_BUILDDIR)

cryptodev_defconfig $(cryptodev_BUILDDIR)/Makefile:
	[ -e $(cryptodev_BUILDDIR) ] || $(MKDIR) $(cryptodev_BUILDDIR)
	$(CP) $(cryptodev_DIR)/* $(cryptodev_BUILDDIR)/
	$(MAKE) -C $(cryptodev_BUILDDIR) version.h

cryptodev_modules_install: DESTDIR=$(BUILD_SYSROOT)

cryptodev_install: cryptodev_modules
	$(MAKE) cryptodev_modules_install

cryptodev: $(cryptodev_BUILDDIR)/Makefile
	$(cryptodev_MAKE) $(BUILDPARALLEL:%=-j%)

cryptodev_%: $(cryptodev_BUILDDIR)/Makefile
	$(cryptodev_MAKE) $(BUILDPARALLEL:%=-j%) $(@:cryptodev_%=%)

#------------------------------------
#
libasound_CFGPARAM_$(APP_PLATFORM)+=--disable-topology
$(eval $(call AC_BUILD3_HEAD,libasound \
    $(PKGDIR2)/alsa-lib \
	$(BUILDDIR2)/libasound-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,libasound))

libasound_footprint $(libasound_BUILDDIR)_footprint:
	[ -d $(dir $(libasound_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(libasound_BUILDDIR)_footprint)
	echo "--disable-topology" > $(libasound_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,libasound))
$(eval $(call AC_BUILD3_DISTCLEAN,libasound))
$(eval $(call AC_BUILD3_FOOT,libasound))

#------------------------------------
#
zlib_DIR=$(PKGDIR2)/zlib
zlib_BUILDDIR=$(BUILDDIR2)/zlib-$(APP_BUILD)
zlib_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(zlib_BUILDDIR)

zlib_PKG=$(dir $(zlib_BUILDDIR))/zlib-pkg.tar

zlib_pkg $(zlib_PKG):
	$(call GIT_ARCHIVE,$(zlib_PKG),$(zlib_DIR))

zlib_defconfig $(zlib_BUILDDIR)/configure.log: | $(zlib_PKG)
	# [ -d "$(zlib_BUILDDIR)" ] || \
	#   git clone $(zlib_DIR) $(zlib_BUILDDIR)
	[ -d $(zlib_BUILDDIR) ] || $(MKDIR) $(zlib_BUILDDIR)
	tar -xvf $(zlib_PKG) -C $(zlib_BUILDDIR) --strip-components=1
	cd $(zlib_BUILDDIR) && \
	  prefix= CROSS_PREFIX=$(CROSS_COMPILE) CFLAGS="-fPIC" ./configure

zlib_distclean:
	$(RM) $(zlib_BUILDDIR)

zlib_install: DESTDIR=$(BUILD_SYSROOT)

zlib__footprint $(zlib_BUILDDIR)_footprint:
	[ -d $(dir $(zlib_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(zlib_BUILDDIR)_footprint)
	echo "-fPIC" > $(zlib_BUILDDIR)_footprint

# zlib_dist_install: DESTDIR=$(BUILD_SYSROOT)
# zlib_dist_install:
# 	echo "-fPIC" > $(zlib_BUILDDIR)_footprint
# 	$(call RUN_DIST_INSTALL1,zlib,$(zlib_BUILDDIR)/configure.log)

$(eval $(call AC_BUILD3_DIST_INSTALL,zlib,$(zlib_BUILDDIR)/configure.log))

zlib: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE)

zlib_%: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE) $(patsubst _%,%,$(@:zlib%=%))

#------------------------------------
#
$(eval $(call AC_BUILD2,libattr $(PKGDIR2)/attr $(BUILDDIR2)/attr-$(APP_BUILD)))

#------------------------------------
# dep: libattr
#
libacl_PKGDEP=libattr
$(eval $(call AC_BUILD2,libacl $(PKGDIR2)/acl $(BUILDDIR2)/acl-$(APP_BUILD)))

#------------------------------------
#
lzo_CFGPARAM_$(APP_PLATFORM)+=--enable-shared

$(eval $(call AC_BUILD3_HEAD,lzo $(PKGDIR2)/lzo $(BUILDDIR2)/lzo-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,lzo))

lzo_footprint $(lzo_BUILDDIR)_footprint:
	[ -d $(dir $(lzo_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(lzo_BUILDDIR)_footprint)
	echo "--enable-shared" > $(lzo_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,lzo))
$(eval $(call AC_BUILD3_DISTCLEAN,lzo))
$(eval $(call AC_BUILD3_FOOT,lzo))

#------------------------------------
#
$(eval $(call AC_BUILD2,gzip $(PKGDIR2)/gzip $(BUILDDIR2)/gzip-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,expat $(PKGDIR2)/expat $(BUILDDIR2)/expat-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,libiconv $(PKGDIR2)/libiconv $(BUILDDIR2)/libiconv-$(APP_BUILD)))

#------------------------------------
# dep: zlib, libiconv
#
libxml2_PKGDEP=zlib libiconv
libxml2_CFGPARAM_$(APP_PLATFORM)+=--without-python
libxml2_CFGPARAM_LDFLAGS_$(APP_PLATFORM)+=-lz -liconv
$(eval $(call AC_BUILD2,libxml2 $(PKGDIR2)/libxml2 $(BUILDDIR2)/libxml2-$(APP_BUILD)))

#------------------------------------
# dep: libxml2, libacl, libiconv, ncurses, libattr
#
libtextstyle_PKGDEP=libxml2 libacl libiconv ncursesw libattr
$(eval $(call AC_BUILD2,libtextstyle $(PKGDIR2)/gettext/libtextstyle $(BUILDDIR)/libtextstyle-$(APP_BUILD)))

# hack log: remove .la and .pc file
# hack log: skip man1 which failed to generate since cross_compile
$(eval $(call AC_BUILD2,gettextrt $(PKGDIR2)/gettext/gettext-runtime $(BUILDDIR)/gettextrt-$(APP_BUILD)))

# failed to build ...
# gettextool_CFGPARAM_$(APP_PLATFORM)+=--with-installed-libtextstyle \
#     --without-installed-csharp-dll --disable-csharp
# $(eval $(call AC_BUILD2,gettextool $(PKGDIR2)/gettext/gettext-tools $(BUILDDIR)/gettextool-$(APP_BUILD)))

# $(eval $(call AC_BUILD2,gettext $(PKGDIR2)/gettext $(BUILDDIR)/gettext-$(APP_BUILD)))
#------------------------------------
# dep: Gettext expat
#
dbus_PKGDEP=libtextstyle gettextrt expat
dbus_CFGPARAM_$(APP_PLATFORM)+=--without-x
$(eval $(call AC_BUILD2,dbus $(PKGDIR2)/dbus $(BUILDDIR2)/dbus-$(APP_BUILD)))

#------------------------------------
# hack log: failed out-of-tree build
# hack log: failed help2man to generate doc
#
# gperf_DIR=$(PKGDIR2)/gperf
# gperf_BUILDDIR=$(BUILDDIR)/gperf-$(APP_BUILD)
# gperf_MAKE=$(MAKE) -C $(gperf_BUILDDIR)

$(eval $(call AC_BUILD3_HEAD,gperf $(PKGDIR2)/gperf $(BUILDDIR)/gperf-$(APP_BUILD)))

gperf_defconfig $(gperf_BUILDDIR)/Makefile:
	[ -d "$(gperf_BUILDDIR)" ] || $(MKDIR) $(gperf_BUILDDIR)
	$(CP) -a $(gperf_DIR)/* $(gperf_BUILDDIR)/
	cd $(gperf_BUILDDIR) && $(or $(gperf_CFGENV_$(APP_PLATFORM)),$(BUILD_ENV)) \
	  ./configure --host=`$(CC) -dumpmachine` --prefix="" \
	  $(gperf_CFGPARAM_$(APP_PLATFORM)) \
	  CPPFLAGS="$(addprefix -I,$(BUILD_SYSROOT)/include) $(gperf_CFGPARAM_CPPFLAGS_$(APP_PLATFORM))" \
	  LDFLAGS="$(addprefix -L,$(BUILD_SYSROOT)/lib $(BUILD_SYSROOT)/lib64) $(gperf_CFGPARAM_LDFLAGS_$(APP_PLATFORM))"

$(eval $(call AC_BUILD3_DIST_INSTALL,gperf))
$(eval $(call AC_BUILD3_DISTCLEAN,gperf))

gperf_install: DESTDIR=$(BUILD_SYSROOT)

gperf: $(gperf_BUILDDIR)/Makefile
	$(MAKE) -C $(gperf_BUILDDIR)/lib $(BUILDPARALLEL:%=-j%)
	$(MAKE) -C $(gperf_BUILDDIR)/src $(BUILDPARALLEL:%=-j%)

gperf_%: $(gperf_BUILDDIR)/Makefile
	$(MAKE) -C $(gperf_BUILDDIR)/lib $(BUILDPARALLEL:%=-j%) DESTDIR=$(DESTDIR) $(@:gperf_%=%)
	$(MAKE) -C $(gperf_BUILDDIR)/src $(BUILDPARALLEL:%=-j%) DESTDIR=$(DESTDIR) $(@:gperf_%=%)

#------------------------------------
# hack log: failed re-generate xml doc
#
libpam_CFGPARAM_$(APP_PLATFORM)+=--disable-doc #--disable-regenerate-docu
$(eval $(call AC_BUILD3_HEAD,libpam $(PKGDIR2)/libpam $(BUILDDIR2)/libpam-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,libpam $(PKGDIR2)/libpam))
$(eval $(call AC_BUILD3_DIST_INSTALL,libpam $(PKGDIR2)/libpam))
$(eval $(call AC_BUILD3_DISTCLEAN,libpam $(PKGDIR2)/libpam))

libpam_install: $(libpam_BUILDDIR)/Makefile
	$(libpam_MAKE) $(BUILDPARALLEL:%=-j%) $(@:libpam_%=%)
	$(MKDIR) $(DESTDIR)/include/security
	for i in $(libpam_DIR)/libpam/include/security/* \
	    $(libpam_DIR)/libpam_misc/include/security/* \
		$(libpam_DIR)/libpamc/include/security/*; do \
	  mv $(DESTDIR)/include/$$(basename $$i) $(DESTDIR)/include/security/; \
	done

$(eval $(call AC_BUILD3_FOOT,libpam))

#------------------------------------
# libcap
# dep: libpam
#
libcap_DIR=$(PKGDIR2)/libcap
libcap_BUILDDIR=$(BUILDDIR)/libcap-$(APP_BUILD)
libcap_PKGDEP=libpam
libcap_CPPFLAGS_INCS=$(libcap_BUILDDIR)/libcap/include/uapi \
    $(libcap_BUILDDIR)/libcap/include $(BUILD_SYSROOT)/include

libcap_MAKE=$(MAKE) -C $(libcap_BUILDDIR) CROSS_COMPILE=$(CROSS_COMPILE) \
	BUILD_CC=gcc DESTDIR=$(DESTDIR) lib=lib prefix=/ \
	LDFLAGS="-L$(BUILD_SYSROOT)/lib64 -L$(BUILD_SYSROOT)/lib" \
	LIBCAP_INCLUDES="$(addprefix -I,$(libcap_CPPFLAGS_INCS))"
ifneq ($(strip $(wildcard $(BUILD_SYSROOT)/include/security/pam_modules.h)),)
libcap_MAKE+=PAM_CAP=yes
endif

libcap_defconfig $(libcap_BUILDDIR)/Makefile:
	[ -d $(libcap_BUILDDIR) ] || $(MKDIR) $(libcap_BUILDDIR)
	$(CP) -a $(libcap_DIR)/* $(libcap_BUILDDIR)/

libcap_dist_install: DESTDIR=$(BUILD_SYSROOT)
libcap_dist_install:
	$(call RUN_DIST_INSTALL1,libcap,$(libcap_BUILDDIR)/Makefile )

libcap: DESTDIR=$(BUILD_SYSROOT)
libcap: | $(libcap_BUILDDIR)/Makefile
	$(libcap_MAKE) $(BUILDPARALLEL:%=-j%)

libcap_%: DESTDIR=$(BUILD_SYSROOT)
libcap_%: | $(libcap_BUILDDIR)/Makefile
	$(libcap_MAKE) $(BUILDPARALLEL:%=-j%) $(@:libcap_%=%)

#------------------------------------
# systemd
# pyenv: meson ninja
# dep: libcap dbus util-linux gperf pcre2
#
systemd_DIR=$(PKGDIR2)/systemd
systemd_BUILDDIR=$(BUILDDIR)/systemd-$(APP_BUILD)
systemd_PKGDEP=libcap dbus utilinux gperf pcre2
systemd_MAKE=$(MAKE) -C $(systemd_BUILDDIR)
ifneq ($(strip $(filter bpi,$(APP_PLATFORM))),)
systemd_MESONS_SETUPARGS+=--cross-file=$(PROJDIR)/builder/meson-bpi.ini
endif

$(eval $(call AC_BUILD3_HEAD,libnl $(PKGDIR2)/libnl $(BUILDDIR2)/libnl-$(APP_BUILD)))


#   -Dmount-path=$(BUILD_SYSROOT)/bin/mount \
#   -Dumount-path=$(BUILD_SYSROOT)/bin/umount \

systemd_defconfig $(systemd_BUILDDIR)/build.ninja:
	[ -d $(systemd_BUILDDIR) ] || $(MKDIR) $(systemd_BUILDDIR)
	. $(BUILDDIR)/pyenv/bin/activate && \
	  cd $(systemd_DIR) && \
	  $(BUILD_PKGCFG_ENV) meson setup $(systemd_MESONS_SETUPARGS) \
		  --prefix=/ --sysconfdir=/etc \
	      --localstatedir=/var -Dblkid=true -Dbuildtype=release \
		  -Ddefault-dnssec=no -Dfirstboot=false -Dinstall-tests=false \
          -Dkmod-path=/bin/kmod -Dldconfig=false \
		  -Dtelinit-path=/bin/systemctl \
          -Drootprefix= -Drootlibdir=/lib -Dsplit-usr=true \
		  -Dsulogin-path=/sbin/sulogin -Dsysusers=false \
		  -Db_lto=false -Drpmmacrosdir=no \
		  -Dc_args="-I$(BUILD_SYSROOT)/include" \
		  -Dc_link_args="-L$(BUILD_SYSROOT)/lib -luuid" \
		  $(systemd_BUILDDIR)

systemd_dist_install: DESTDIR=$(BUILD_SYSROOT)
systemd_dist_install:
	$(RM) $(systemd_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,systemd,$(systemd_BUILDDIR)/build.ninja)

systemd_install: systemd
	. $(BUILDDIR)/pyenv/bin/activate && \
	  DESTDIR=$(DESTDIR) $(BUILD_PKGCFG_ENV) meson install \
	    -C $(systemd_BUILDDIR)

systemd: DESTDIR=$(BUILD_SYSROOT)
systemd: | $(systemd_BUILDDIR)/build.ninja
	. $(BUILDDIR)/pyenv/bin/activate && \
	  DESTDIR=$(DESTDIR) $(BUILD_PKGCFG_ENV) meson compile \
	      -C $(systemd_BUILDDIR) $(BUILDPARALLEL:%=-j%)

systemd_%: DESTDIR=$(BUILD_SYSROOT)
systemd_%: | $(systemd_BUILDDIR)/build.ninja
	. $(BUILDDIR)/pyenv/bin/activate && \
	  DESTDIR=$(DESTDIR) $(BUILD_PKGCFG_ENV) meson compile \
	    -C $(systemd_BUILDDIR) $(BUILDPARALLEL:%=-j%) $(@:systemd_%=%)

#------------------------------------
#
libdaemon_DIR=$(PKGDIR2)/libdaemon
libdaemon_BUILDDIR?=$(BUILDDIR2)/libdaemon-$(APP_BUILD)
libdaemon_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(libdaemon_BUILDDIR)

libdaemon_defconfig $(libdaemon_BUILDDIR)/Makefile:
	[ -d "$(libdaemon_BUILDDIR)" ] || $(MKDIR) $(libdaemon_BUILDDIR)
	[ -f "$(libdaemon_DIR)/configure" ] || { \
	  cd $(libdaemon_DIR) && NOCONFIGURE=1 ./bootstrap.sh; \
	}
	cd $(libdaemon_BUILDDIR) && \
	  echo -n > config.cache && \
	  echo "ac_cv_func_setpgrp_void=yes" >> config.cache && \
	  $(BUILD_ENV) $(libdaemon_DIR)/configure --cache-file=config.cache \
	    --host=`$(CC) -dumpmachine` --prefix=

libdaemon_install: DESTDIR=$(BUILD_SYSROOT)

libdaemon_dist_install: DESTDIR=$(BUILD_SYSROOT)
libdaemon_dist_install:
	$(RM) $(libdaemon_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,libdaemon,$(libdaemon_BUILDDIR)/Makefile)

libdaemon: $(libdaemon_BUILDDIR)/Makefile
	$(libdaemon_MAKE) $(BUILDPARALLEL:%=-j%)

libdaemon_%: $(libdaemon_BUILDDIR)/Makefile
	$(libdaemon_MAKE) $(BUILDPARALLEL:%=-j%) $(@:libdaemon_%=%)

#------------------------------------
# opt
# apt: xmltoman
# dep: expat libdaemon libevent
#
avahi_PKGDEP=expat libdaemon libevent
avahi_CFGPARAM_$(APP_PLATFORM)=--with-distro=none \
    $(addprefix --disable-,glib gobject qt5 gtk3 dbus gdbm python)
# avahi_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)=-I$(BUILD_SYSROOT)/include/ncursesw
avahi_CFGPARAM_$(APP_PLATFORM)+=LIBEVENT_CFLAGS=-I$(BUILD_SYSROOT)/include
avahi_CFGPARAM_$(APP_PLATFORM)+=LIBEVENT_LIBS=-levent
avahi_CFGPARAM_$(APP_PLATFORM)+=LIBDAEMON_CFLAGS=-I$(BUILD_SYSROOT)/include
avahi_CFGPARAM_$(APP_PLATFORM)+=LIBDAEMON_LIBS=-ldaemon

$(eval $(call AC_BUILD3_HEAD,avahi $(PKGDIR2)/avahi $(BUILDDIR2)/avahi-$(APP_BUILD)))

avahi_defconfig $(avahi_BUILDDIR)/Makefile:
	if [ -x $(avahi_DIR)/configure ]; then \
	  true; \
	elif [ -x $(avahi_DIR)/autogen.sh ]; then \
	  cd $(avahi_DIR) && NOCONFIGURE=1 ./autogen.sh; \
	else \
	  cd $(avahi_DIR) && autoreconf -fiv; \
	fi
	[ -d "$(avahi_BUILDDIR)" ] || $(MKDIR) $(avahi_BUILDDIR)
	cd $(avahi_BUILDDIR) && \
	  $(or $(avahi_CFGENV_$(APP_PLATFORM)),$(BUILD_ENV)) \
	  $(avahi_DIR)/configure --host=`$(CC) -dumpmachine` --prefix="" \
	    $(avahi_CFGPARAM_$(APP_PLATFORM)) \
		CPPFLAGS="$(addprefix -I,$(BUILD_SYSROOT)/include $(avahi_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)))" \
		LDFLAGS="$(addprefix -L,$(BUILD_SYSROOT)/lib $(BUILD_SYSROOT)/lib64 $(avahi_CFGPARAM_LDFLAGS_$(APP_PLATFORM)))"

$(eval $(call AC_BUILD3_DIST_INSTALL,avahi))
$(eval $(call AC_BUILD3_DISTCLEAN,avahi))
$(eval $(call AC_BUILD3_FOOT,avahi))

#------------------------------------
#
e2fsprogs_CFGPARAM_$(APP_PLATFORM)+=$(addprefix --enable-,subset libuuid)

$(eval $(call AC_BUILD3_HEAD,e2fsprogs $(PKGDIR2)/e2fsprogs $(BUILDDIR2)/e2fsprogs-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,e2fsprogs))

e2fsprogs_footprint $(e2fsprogs_BUILDDIR)_footprint:
	[ -d $(dir $(e2fsprogs_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(e2fsprogs_BUILDDIR)_footprint)
	echo "$(addprefix --enable-,subset libuuid)" > $(e2fsprogs_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,e2fsprogs))
$(eval $(call AC_BUILD3_DISTCLEAN,e2fsprogs))
$(eval $(call AC_BUILD3_FOOT,e2fsprogs))

#------------------------------------
# ubifs dep: lzo zlib uuid (e2fsprogs)
# jfss2 dep: acl zlib
#
mtdutil_CFGPARAM_$(APP_PLATFORM)+=--without-zstd
mtdutil_PKGDEP=lzo zlib e2fsprogs libacl

$(eval $(call AC_BUILD3_HEAD,mtdutil $(PKGDIR2)/mtd-utils $(BUILDDIR2)/mtdutil-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,mtdutil))

mtdutil_footprint $(mtdutil_BUILDDIR)_footprint:
	[ -d $(dir $(mtdutil_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(mtdutil_BUILDDIR)_footprint)
	echo "--without-zstd" > $(mtdutil_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,mtdutil))
$(eval $(call AC_BUILD3_DISTCLEAN,mtdutil))
$(eval $(call AC_BUILD3_FOOT,mtdutil))

#------------------------------------
# gmp-6.2.1
#
ifneq ($(strip $(BUILD_CFLAGS2_$(APP_PLATFORM))),)
gmp_CFGPARAM_$(APP_PLATFORM)+="CFLAGS=$(BUILD_CFLAGS2_$(APP_PLATFORM))"
endif
$(eval $(call AC_BUILD2,gmp $$(PKGDIR2)/gmp $$(BUILDDIR2)/gmp-$(APP_BUILD)))

#------------------------------------
# opt
#
fftw_CFGPARAM_$(APP_PLATFORM)+=--disable-fortran
fftw_CFGPARAM_sa7715+=--enable-neon --enable-single

fftw_footprint $(fftw_BUILDDIR)_footprint:
	[ -d $(dir $(fftw_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(fftw_BUILDDIR)_footprint)
	echo "--disable-fortran" > $(fftw_BUILDDIR)_footprint

$(eval $(call AC_BUILD2,fftw $(PKGDIR2)/fftw $(BUILDDIR2)/fftw-$(APP_BUILD)))

#------------------------------------
#
ncursesw_DIR=$(PKGDIR2)/ncurses
ncursesw_BUILDDIR?=$(BUILDDIR2)/ncursesw-$(APP_BUILD)
ncursesw_TINFODIR=/usr/share/terminfo

# refine to comma saperated list when use in tic
ncursesw_TINFO=ansi ansi-m color_xterm,linux,pcansi-m,rxvt-basic,vt52,vt100 \
  vt102,vt220,xterm,tmux-256color,screen-256color,xterm-256color screen

ncursesw_DEF_CFG=$(ncursesw_DIR)/configure --prefix= --with-shared \
  --with-termlib --with-ticlib --enable-widec --enable-pc-files \
  --with-default-terminfo-dir=$(ncursesw_TINFODIR)

ifneq ($(strip $(BUILD_CFLAGS2_$(APP_PLATFORM))),)
ncursesw_DEF_CFG+="CFLAGS=$(BUILD_CFLAGS2_$(APP_PLATFORM))"
endif

ncursesw_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(ncursesw_BUILDDIR)

ncursesw_host_install: DESTDIR=$(PROJDIR)/tool
ncursesw_host_install: ncursesw_BUILDDIR=$(BUILDDIR2)/ncursesw-host
ncursesw_host_install:
	if [ ! -f $(ncursesw_BUILDDIR)/Makefile ]; then \
	  ( [ -d "$(ncursesw_BUILDDIR)" ] || $(MKDIR) $(ncursesw_BUILDDIR) ) && \
	  cd $(ncursesw_BUILDDIR) && $(ncursesw_DEF_CFG) --with-pkg-config=/lib; \
	fi
	$(ncursesw_MAKE) install
	echo "INPUT(-lncursesw)" > $(DESTDIR)/lib/libcurses.so;
	for i in ncurses form panel menu tinfo; do \
	  echo "INPUT(-l$${i}w)" > $(DESTDIR)/lib/lib$${i}.so; \
	done

ncursesw_host_dist_install: DESTDIR=$(PROJDIR)/tool
ncursesw_host_dist_install: ncursesw_BUILDDIR=$(BUILDDIR2)/ncursesw-host
ncursesw_host_dist_install:
	[ -d "$(dir $(ncursesw_BUILDDIR)_footprint)" ] || $(MKDIR) $(dir $(ncursesw_BUILDDIR)_footprint)
	echo "$(ncursesw_DEF_CFG) --with-pkg-config=/lib" > $(ncursesw_BUILDDIR)_footprint
	if ! md5sum -c "$(ncursesw_BUILDDIR).md5sum"; then \
	  $(MAKE) DESTDIR=$(ncursesw_BUILDDIR)_destdir \
	      ncursesw_host_install && \
	  tar -cvf $(ncursesw_BUILDDIR).tar \
	      -C $(dir $(ncursesw_BUILDDIR)_destdir) \
	      $(notdir $(ncursesw_BUILDDIR)_destdir) && \
	  md5sum $(ncursesw_BUILDDIR).tar \
	      $(wildcard $(ncursesw_BUILDDIR)_footprint) \
	      $(ncursesw_BUILDDIR)/Makefile \
		  > $(ncursesw_BUILDDIR).md5sum && \
	  $(RM) $(ncursesw_BUILDDIR)_destdir; \
	fi
	[ -d "$(DESTDIR)" ] || $(MKDIR) $(DESTDIR)
	tar -xvf $(ncursesw_BUILDDIR).tar --strip-components=1 \
	    -C $(DESTDIR)

ncursesw_defconfig $(ncursesw_BUILDDIR)/Makefile:
	[ -d $(ncursesw_BUILDDIR) ] || $(MKDIR) $(ncursesw_BUILDDIR)
	cd $(ncursesw_BUILDDIR) && \
	  $(ncursesw_DEF_CFG) --host=`$(CC) -dumpmachine` \
	  --disable-db-install --without-tests --disable-stripping \
	  --without-manpages

ncursesw_distclean:
	$(RM) $(ncursesw_BUILDDIR)

ncursesw_install: DESTDIR=$(BUILD_SYSROOT)
ncursesw_install: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE) install
	echo "INPUT(-lncursesw)" > $(DESTDIR)/lib/libcurses.so;
	for i in ncurses form panel menu tinfo; do \
	  echo "INPUT(-l$${i}w)" > $(DESTDIR)/lib/lib$${i}.so; \
	done

ncursesw_dist_install: DESTDIR=$(BUILD_SYSROOT)
ncursesw_dist_install:
	echo "$(ncursesw_DEF_CFG) --disable-db-install --without-tests \
	  --disable-stripping --without-manpages" > $(ncursesw_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,ncursesw,$(ncursesw_BUILDDIR)/Makefile)

# opt dep: [ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_install
ncursesw_terminfo_install: DESTDIR=$(BUILD_SYSROOT)
ncursesw_terminfo_install: tic=LD_LIBRARY_PATH=$(PROJDIR)/tool/lib \
    TERMINFO=$(PROJDIR)/tool/$(ncursesw_TINFODIR) $(PROJDIR)/tool/bin/tic
ncursesw_terminfo_install: ncursesw_TINFO2=$(subst $(SPACE),$(COMMA),$(sort \
    $(subst $(COMMA),$(SPACE),$(ncursesw_TINFO))))
ncursesw_terminfo_install:
	[ -d $(DESTDIR)/$(ncursesw_TINFODIR) ] || $(MKDIR) $(DESTDIR)/$(ncursesw_TINFODIR)
	$(tic) -s -1 -I -e'$(ncursesw_TINFO2)' $(ncursesw_DIR)/misc/terminfo.src \
	    > $(BUILDDIR)/terminfo.src; \
	$(tic) -s -o $(DESTDIR)/$(ncursesw_TINFODIR) $(BUILDDIR)/terminfo.src; \

ncursesw_terminfo_dist_install: DESTDIR=$(BUILD_SYSROOT)
ncursesw_terminfo_dist_install: terminfo_BUILDDIR=$(BUILDDIR2)/ncursesw_terminfo-$(APP_BUILD)
ncursesw_terminfo_dist_install:
	echo "tic -s -1 -I" > $(terminfo_BUILDDIR)_footprint
	echo "$(ncursesw_DEF_CFG)" >> $(terminfo_BUILDDIR)_footprint
	echo "$(ncursesw_TINFO)" >> $(terminfo_BUILDDIR)_footprint
	if ! md5sum -c "$(terminfo_BUILDDIR).md5sum"; then \
	  $(MAKE) DESTDIR=$(terminfo_BUILDDIR)_destdir \
	      ncursesw_terminfo_install && \
	  tar -cvf $(terminfo_BUILDDIR).tar -C $(dir $(terminfo_BUILDDIR)_destdir) \
	      $(notdir $(terminfo_BUILDDIR)_destdir) && \
	  md5sum $(terminfo_BUILDDIR).tar $(wildcard $(terminfo_BUILDDIR)_footprint) $(ncursesw_BUILDDIR)/Makefile \
	      > $(terminfo_BUILDDIR).md5sum && \
	  $(RM) $(terminfo_BUILDDIR)_destdir; \
	fi
	[ -d "$(DESTDIR)" ] || $(MKDIR) $(DESTDIR)
	tar -xvf $(terminfo_BUILDDIR).tar --strip-components=1 -C $(DESTDIR)

ncursesw: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE)

ncursesw_%: $(ncursesw_BUILDDIR)/Makefile
	$(ncursesw_MAKE) $(@:ncursesw_%=%)

#------------------------------------
#
utilinux_CFGPARAM_$(APP_PLATFORM)+=--without-python --disable-use-tty-group \
    --disable-makeinstall-chown --disable-makeinstall-setuid
$(eval $(call AC_BUILD2,utilinux $(PKGDIR2)/util-linux $(BUILDDIR)/utilinux-$(APP_BUILD)))

#------------------------------------
# dep: libudev (systemd)
#
libusb_PKGDEP=systemd
$(eval $(call AC_BUILD2,libusb $(PKGDIR2)/libusb $(BUILDDIR2)/libusb-$(APP_BUILD)))

#------------------------------------
# dep: libusb
#
openocd_PKGDEP=libusb
$(eval $(call AC_BUILD2,openocd $(PKGDIR2)/openocd $(BUILDDIR2)/openocd-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,libmnl $(PKGDIR2)/libmnl $(BUILDDIR2)/libmnl-$(APP_BUILD)))

#------------------------------------
# dep: ncurses mnl
#
ethtool_PKGDEP=ncursesw libmnl
ethtool_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
ethtool_CFGPARAM_LDFLAGS_$(APP_PLATFORM)+=-lmnl
ethtool_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD2,ethtool $(PKGDIR2)/ethtool $(BUILDDIR2)/ethtool-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,iperf3 $(PKGDIR2)/iperf3 $(BUILDDIR2)/iperf3-$(APP_BUILD)))

#------------------------------------
#
openssl_DIR=$(PKGDIR2)/openssl
openssl_BUILDDIR=$(BUILDDIR2)/openssl-$(APP_BUILD)
openssl_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(openssl_BUILDDIR)

ifneq ($(strip $(filter ub20 bpi,$(APP_ATTR))),)
openssl_CFGPARAM_$(APP_PLATFORM)+=linux-generic64
else
openssl_CFGPARAM_$(APP_PLATFORM)+=linux-generic32
endif

openssl_defconfig $(openssl_BUILDDIR)/configdata.pm:
	[ -d $(openssl_BUILDDIR) ] || $(MKDIR) $(openssl_BUILDDIR)
	cd $(openssl_BUILDDIR) && \
	  $(openssl_DIR)/Configure $(openssl_CFGPARAM_$(APP_PLATFORM)) \
	    --cross-compile-prefix=$(CROSS_COMPILE) --prefix=/ \
	    --openssldir=/lib/ssl no-tests no-hw-padlock \
		-L$(BUILD_SYSROOT)/lib -I$(BUILD_SYSROOT)/include

openssl_install: DESTDIR=$(BUILD_SYSROOT)
openssl_install: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) install_sw install_ssldirs

openssl_footprint $(openssl_BUILDDIR)_footprint:
	[ -d $(dir $(openssl_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(openssl_BUILDDIR)_footprint)
	echo "openssl_CFGPARAM_$(APP_PLATFORM) --openssldir=/lib/ssl" > $(openssl_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,openssl))

openssl: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE)

openssl_%: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) $(@:openssl_%=%)

#------------------------------------
#
libevent_CFGPARAM_$(APP_PLATFORM)+=--disable-openssl

$(eval $(call AC_BUILD3_HEAD,libevent $(PKGDIR2)/libevent $(BUILDDIR2)/libevent-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,libevent))

libevent_footprint $(libevent_BUILDDIR)_footprint:
	[ -d $(dir $(libevent_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(libevent_BUILDDIR)_footprint)
	echo "--disable-openssl" > $(libevent_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,libevent))
$(eval $(call AC_BUILD3_DISTCLEAN,libevent))
$(eval $(call AC_BUILD3_FOOT,libevent))

#------------------------------------
# dep ncursesw libevent
#
tmux_PKGDEP=ncursesw libevent
tmux_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
tmux_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD2,tmux $(PKGDIR2)/tmux $(BUILDDIR2)/tmux-$(APP_BUILD)))

#------------------------------------
#
libcjson_DIR=$(PKGDIR2)/cjson
libcjson_BUILDDIR?=$(BUILDDIR2)/libcjson-$(APP_BUILD)
libcjson_MAKE=$(MAKE) -C $(libcjson_BUILDDIR)

ifneq ($(strip $(filter sa7715 som1 wlsom1,$(APP_ATTR))),)
libcjson_CMAKEPARAM_$(APP_PLATFORM)+=-DCMAKE_SYSTEM_NAME=linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_COMPILER=$(CC) -DCMAKE_CXX_COMPILER=$(C++)
endif

libcjson_defconfig $(libcjson_BUILDDIR)/Makefile:
	[ -d "$(libcjson_BUILDDIR)" ] || $(MKDIR) $(libcjson_BUILDDIR)
	cd $(libcjson_BUILDDIR) && cmake \
	    $(libcjson_CMAKEPARAM_$(APP_PLATFORM)) \
	    -DCMAKE_INSTALL_PREFIX=$(firstword $(CMAKE_INSTALL_PREFIX) $(BUILD_SYSROOT) $(DESTDIR)) \
	    $(libcjson_DIR)

libcjson: $(libcjson_BUILDDIR)/Makefile
	$(libcjson_MAKE) $(BUILDPARALLEL:%=-j%)

libcjson_%: $(libcjson_BUILDDIR)/Makefile
	$(libcjson_MAKE) $(BUILDPARALLEL:%=-j%) $(@:libcjson_%=%)

#------------------------------------
# dep: make libasound_install ncursesw_install
#
alsautils_PKGDEP=ncursesw libasound
alsautils_CFGPARAM_$(APP_PLATFORM)+=--disable-alsatest
alsautils_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
alsautils_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD3_HEAD,alsautils $(PKGDIR2)/alsa-utils $(BUILDDIR2)/alsautils-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,alsautils))

alsautils_footprint $(alsautils_BUILDDIR)_footprint:
	[ -d $(dir $(alsautils_BUILDDIR)_footprint) ] || $(MKDIR) $(dir $(alsautils_BUILDDIR)_footprint)
	echo "--disable-alsatest" > $(alsautils_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,alsautils))
$(eval $(call AC_BUILD3_DISTCLEAN,alsautils))
$(eval $(call AC_BUILD3_FOOT,alsautils))

#------------------------------------
#
libnl_BUILD_INTREE=1

$(eval $(call AC_BUILD3_HEAD,libnl $(PKGDIR2)/libnl $(BUILDDIR2)/libnl-$(APP_BUILD)))

ifneq ($(strip $(libnl_BUILD_INTREE)),)
libnl_defconfig $(libnl_BUILDDIR)/Makefile:
	[ -d "$(libnl_BUILDDIR)" ] || git clone $(libnl_DIR) $(libnl_BUILDDIR)
	[ -x $(libnl_BUILDDIR)/configure ] || { \
	  cd $(libnl_BUILDDIR) && ./autogen.sh; \
	}
	cd $(libnl_BUILDDIR) && \
	  ./configure --host=`$(CC) -dumpmachine` --prefix=
else
$(eval $(call AC_BUILD3_DEFCONFIG,libnl))
endif

$(eval $(call AC_BUILD3_DIST_INSTALL,libnl))
$(eval $(call AC_BUILD3_DISTCLEAN,libnl))
$(eval $(call AC_BUILD3_FOOT,libnl))

#------------------------------------
#
$(eval $(call AC_BUILD3_HEAD,libgpiod $(PKGDIR2)/libgpiod $(BUILDDIR2)/libgpiod-$(APP_BUILD)))
libgpiod_defconfig $(libgpiod_BUILDDIR)/Makefile: $(libgpiod_BUILDDIR)/config.cache
$(libgpiod_BUILDDIR)/config.cache:
	[ -d "$(libgpiod_BUILDDIR)" ] || $(MKDIR) $(libgpiod_BUILDDIR)
	echo "ac_cv_func_malloc_0_nonnull=yes" > $(libgpiod_BUILDDIR)/config.cache
libgpiod_CFGPARAM_$(APP_PLATFORM)+=--cache-file=$(libgpiod_BUILDDIR)/config.cache \
    --enable-tools
$(eval $(call AC_BUILD3_DEFCONFIG,libgpiod))
$(eval $(call AC_BUILD3_DIST_INSTALL,libgpiod))
$(eval $(call AC_BUILD3_DISTCLEAN,libgpiod))
$(eval $(call AC_BUILD3_FOOT,libgpiod))

#------------------------------------
# dep: zlib libasound_install ncursesw_install
#
ff_PKGDEP=zlib libasound ncursesw
ff_DIR=$(PKGDIR2)/ffmpeg
ff_BUILDDIR=$(BUILDDIR2)/ffmpeg-$(APP_PLATFORM)
ff_INCDIR=$(BUILD_SYSROOT)/include $(BUILD_SYSROOT)/include/ncursesw
ff_LIBDIR+=$(BUILD_SYSROOT)/lib64 $(BUILD_SYSROOT)/usr/lib64 \
    $(BUILD_SYSROOT)/lib $(BUILD_SYSROOT)/usr/lib
ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
ff_CFGPARAM_$(APP_PLATFORM)+=--arch=aarch64  --enable-ffplay
else ifneq ($(strip $(filter xm,$(APP_ATTR))),)
ff_CFGPARAM_$(APP_PLATFORM)+=--arch=arm --cpu=cortex-a5 --enable-vfpv3 \
    --enable-ffplay
else
ff_CFGPARAM_$(APP_PLATFORM)+=--enable-debug=  --enable-ffplay
endif

ff_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(ff_BUILDDIR)

ff_defconfig $(ff_BUILDDIR)/config.h:
	[ -d "$(ff_BUILDDIR)" ] || $(MKDIR) $(ff_BUILDDIR)
	cd $(ff_BUILDDIR) && \
	  $(BUILD_PKGCFG_ENV) LD_LIBRARY_PATH=$(PROJDIR)/tool/lib \
	    $(ff_DIR)/configure --target-os=linux --cross_prefix=$(CROSS_COMPILE) \
		--enable-cross-compile $(ff_CFGPARAM_$(APP_PLATFORM)) \
		--prefix=/ --disable-iconv --enable-pic --enable-shared \
	    --enable-hardcoded-tables --enable-pthreads \
	    --extra-cflags="$(addprefix -I,$(ff_INCDIR)) -D_REENTRANT" \
	    --extra-ldflags="$(addprefix -L,$(ff_LIBDIR))"

ff_install: DESTDIR=$(BUILD_SYSROOT)

ff_dist_install: DESTDIR=$(BUILD_SYSROOT)
ff_dist_install:
	$(RM) $(ff_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,ff,$(ff_BUILDDIR)/config.h)

ff: $(ff_BUILDDIR)/config.h
	$(ff_MAKE) $(BUILDPARALLEL:%=-j%)

ff_%: $(ff_BUILDDIR)/config.h
	$(ff_MAKE) $(BUILDPARALLEL:%=-j%) $(@:ff_%=%)

#------------------------------------
#
ap6212_DIR=$(PROJDIR)/package/ap6212

ap6212_install: DESTDIR=$(BUILD_SYSROOT)
ap6212_install: FW_PREFIX=/lib/firmware/brcm
ap6212_install:
	[ -d $(DESTDIR)$(FW_PREFIX) ] || $(MKDIR) $(DESTDIR)$(FW_PREFIX)
	$(CP) $(ap6212_DIR)/bpi/fw_bcm43438a1.bin $(DESTDIR)$(FW_PREFIX)/
	ln -sf fw_bcm43438a1.bin $(DESTDIR)$(FW_PREFIX)/brcmfmac43430-sdio.bin
	$(CP) $(ap6212_DIR)/bpi/nvram_ap6212.txt $(DESTDIR)$(FW_PREFIX)/
	ln -sf nvram_ap6212.txt $(DESTDIR)$(FW_PREFIX)/brcmfmac43430-sdio.txt

#------------------------------------
ath9k_install: DESTDIR=$(BUILD_SYSROOT)
ath9k_install: FW_PREFIX=/lib/firmware/ath9k_htc
ath9k_install:
	[ -d $(DESTDIR)$(FW_PREFIX) ] || $(MKDIR) $(DESTDIR)$(FW_PREFIX)
	@rsync -avv /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw \
	    $(DESTDIR)$(FW_PREFIX)/

#------------------------------------
# dep: libnl3
#
iw_PKGDEP=libnl
iw_DIR=$(PKGDIR2)/iw
iw_BUILDDIR=$(BUILDDIR2)/iw-$(APP_BUILD)
# iw_INCDIR=$(BUILD_SYSROOT)/include $(BUILD_SYSROOT)/include/libnl3
iw_LIBDIR=$(BUILD_SYSROOT)/lib

iw_MAKE=$(BUILD_PKGCFG_ENV) PREFIX=/ DESTDIR=$(DESTDIR) CC=$(CC) \
    LDFLAGS="$(addprefix -L,$(iw_LIBDIR))" $(MAKE) -C $(iw_BUILDDIR)

iw_defconfig $(iw_BUILDDIR)/Makefile:
	[ -d $(iw_BUILDDIR) ] || $(MKDIR) $(iw_BUILDDIR)
	$(CP) $(iw_DIR)/* $(iw_BUILDDIR)/

iw_install: DESTDIR=$(BUILD_SYSROOT)

iw_dist_install: DESTDIR=$(BUILD_SYSROOT)
iw_dist_install:
	$(RM) $(iw_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,iw,$(iw_BUILDDIR)/Makefile)

iw_distclean:
	$(RM) $(iw_BUILDDIR)

iw: | $(iw_BUILDDIR)/Makefile
	$(iw_MAKE)

iw_%: | $(iw_BUILDDIR)/Makefile
	$(iw_MAKE) $(@:iw_%=%)

#------------------------------------
# opt
#
wirelesstools29_MAKEPARAM_$(APP_PLATFORM)=CC=$(CC) AR=$(AR) RANLIB=$(RANLIB) \
    PREFIX=$(DESTDIR)
$(eval $(call AC_BUILD3_HEAD,wirelesstools29 $(PKGDIR2)/wireless_tools.29 $(BUILDDIR2)/wirelesstools29-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DISTCLEAN,wirelesstools29))
$(eval $(call AC_BUILD3_DIST_INSTALL,wirelesstools29))
$(eval $(call AC_BUILD3_FOOT,wirelesstools29))

#------------------------------------
# dep: openssl, libnl, linux_headers
#
wpasup_PKGDEP=openssl libnl
wpasup_DIR=$(PKGDIR2)/wpa_supplicant
wpasup_BUILDDIR=$(BUILDDIR2)/wpasup-$(APP_BUILD)
wpasup_MAKE=$(MAKE) CC=$(CC) LIBNL_INC="$(BUILD_SYSROOT)/include/libnl3" \
  EXTRA_CFLAGS="-I$(BUILD_SYSROOT)/include" LDFLAGS="-L$(BUILD_SYSROOT)/lib" \
  DESTDIR=$(DESTDIR) LIBDIR=/lib BINDIR=/sbin INCDIR=/include \
  -C $(wpasup_BUILDDIR)/wpa_supplicant

wpasup_defconfig $(wpasup_BUILDDIR)/wpa_supplicant/.config:
	if [ ! -d "$(wpasup_BUILDDIR)" ]; then \
	  $(MKDIR) $(wpasup_BUILDDIR) && \
	  $(CP) $(wpasup_DIR)/* $(wpasup_BUILDDIR); \
	fi
	if [ -f "$(PROJDIR)/wpa_supplicant.config" ]; then \
	  $(CP) $(PROJDIR)/wpa_supplicant.config \
	    $(wpasup_BUILDDIR)/wpa_supplicant/.config; \
	else \
	  $(CP) $(wpasup_BUILDDIR)/wpa_supplicant/defconfig \
	    $(wpasup_BUILDDIR)/wpa_supplicant/.config; \
	fi

wpasup_install: DESTDIR=$(BUILD_SYSROOT)
wpasup_install: wpasup_all
	$(wpasup_MAKE) $(BUILDPARALLEL:%=-j%) install

wpasup_dist_install: DESTDIR=$(BUILD_SYSROOT)
wpasup_dist_install:
	echo "libnl3" > $(wpasup_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,wpasup,$(wpasup_BUILDDIR)/wpa_supplicant/.config)

wpasup: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE) $(BUILDPARALLEL:%=-j%)

wpasup_%: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE) $(BUILDPARALLEL:%=-j%) $(@:wpasup_%=%)

#------------------------------------
# wpa_supplicant-2.9
# dep: openssl, libnl, linux_headers
#
hostapd_PKGDEP=openssl libnl
hostapd_DIR=$(PKGDIR2)/hostapd
hostapd_BUILDDIR?=$(BUILDDIR2)/hostapd-$(APP_BUILD)
hostapd_MAKE=$(MAKE) CC=$(CC) LIBNL_INC="$(BUILD_SYSROOT)/include/libnl3" \
    EXTRA_CFLAGS="-I$(BUILD_SYSROOT)/include" LDFLAGS="-L$(BUILD_SYSROOT)/lib" \
    DESTDIR=$(DESTDIR) LIBDIR=/lib BINDIR=/sbin INCDIR=/include \
    -C $(hostapd_BUILDDIR)/hostapd

hostapd_defconfig $(hostapd_BUILDDIR)/hostapd/.config:
	if [ ! -d "$(hostapd_BUILDDIR)" ]; then \
	  $(MKDIR) $(hostapd_BUILDDIR) && \
	  $(CP) $(hostapd_DIR)/* $(hostapd_BUILDDIR); \
	fi
	if [ -f "$(PROJDIR)/hostapd.config" ]; then \
	  $(CP) $(PROJDIR)/hostapd.config \
	    $(hostapd_BUILDDIR)/hostapd/.config; \
	else \
	  $(CP) $(hostapd_BUILDDIR)/hostapd/defconfig \
	    $(hostapd_BUILDDIR)/hostapd/.config; \
	fi

hostapd_install: DESTDIR=$(BUILD_SYSROOT)

hostapd_dist_install: DESTDIR=$(BUILD_SYSROOT)
hostapd_dist_install:
	echo "libnl3" > $(hostapd_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,hostapd,$(hostapd_BUILDDIR)/Makefile)

hostapd: $(hostapd_BUILDDIR)/hostapd/.config
	$(hostapd_MAKE) $(BUILDPARALLEL:%=-j%)

hostapd_%: $(hostapd_BUILDDIR)/hostapd/.config
	$(hostapd_MAKE) $(BUILDPARALLEL:%=-j%) $(@:hostapd_%=%)

#------------------------------------
# sqlite-3.37.0
#
$(eval $(call AC_BUILD2,sqlite3 $(PKGDIR2)/sqlite $(BUILDDIR2)/sqlite3-$(APP_BUILD)))

#------------------------------------
# pcre2-10.38-85-g419e3c6
#
$(eval $(call AC_BUILD2,pcre2 $(PKGDIR2)/pcre2 $(BUILDDIR2)/pcre2-$(APP_BUILD)))

#------------------------------------
# dep: libcjson uriparse libgpiod
#
admin_bindir?=/bin
admin_CFGPARAM_$(APP_PLATFORM)+=--bindir=$(admin_bindir) --enable-air192
admin_CFGPARAM_$(APP_PLATFORM)+="CFLAGS=$(BUILD_CFLAGS2_$(APP_PLATFORM))"
admin_CFGPARAM_ub20+=--enable-debug USER_PREFIX="./"
ifneq ($(strip $(filter debug1,$(APP_ATTR))),)
admin_CFGPARAM_sa7715+=--enable-debug
endif

$(eval $(call AC_BUILD3_HEAD,admin $(PROJDIR)/package/admin $(BUILDDIR2)/admin-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,admin))
$(eval $(call AC_BUILD3_DIST_INSTALL,admin,$(admin_DIR)/include/admin/sa7715.h))
$(eval $(call AC_BUILD3_DISTCLEAN,admin))

#admin_install: admin_cgi_install

admin_cgi_install: DESTDIR=$(BUILD_SYSROOT)
admin_cgi_install:
	[ -d $(DESTDIR)/var/cgi-bin ] || $(MKDIR) $(DESTDIR)/var/cgi-bin
	for i in admin_fwupd admin_spkcal admin_wificfg admin_ethcfg admin_acccfg \
	    admin_fwupd2 $(admin_cgi_EXTRA); do \
	  [ -e $(DESTDIR)/var/cgi-bin/$${i}.cgi ] || \
	    ln -sf ../../$(admin_bindir)/admin $(DESTDIR)/var/cgi-bin/$${i}.cgi; \
	done

# use mod_setenv to set LD_LIBRARY_PATH for cgi
# DESTDIR=`pwd`/build/sysroot-ub20 ~/07_sw/lighttpd/sbin/lighttpd -m ~/07_sw/lighttpd/lib -f build/sysroot-ub20/etc/lighttpd.conf -D
admin_host: DESTDIR=$(BUILD_SYSROOT)
admin_host: APP_ATTR=ub20
admin_host:
	$(MAKE) libcjson_install uriparser_install admin_install
	[ -d "$(DESTDIR)/var/www" ] || $(MKDIR) $(DESTDIR)/var/www
	for i in $(admin_DIR)/test/*.html; do \
	  ln -sf $$i $(DESTDIR)/var/www/; \
	done
	ln -sf $(abspath $(PROJDIR)/prebuilt/sa7715/common/var/www/admin.html) $(DESTDIR)/var/www/admin-target.html
	[ -d $(DESTDIR)/var/cgi-bin ] || $(MKDIR) $(DESTDIR)/var/cgi-bin
	for i in $(admin_DIR)/test/*.cgi; do \
	  ln -sf $$i $(DESTDIR)/var/cgi-bin/; \
	done
	[ -d "$(DESTDIR)/etc" ] || $(MKDIR) $(DESTDIR)/etc
	ln -sf $(admin_DIR)/test/lighttpd.conf $(DESTDIR)/etc/
	$(MAKE) admin_cgi_EXTRA="cgienv" admin_cgi_install
	[ -d "$(DESTDIR)/media" ] || $(MKDIR) $(DESTDIR)/media
	ln -sf $(PROJDIR)/destdir/ota.tar.gz $(DESTDIR)/media/ota-host.tar.gz
	[ -e $(DESTDIR)/media/sa7715 ] || ln -sf $(PROJDIR)/.. $(DESTDIR)/media/sa7715
	for i in var/run; do \
	  [ -d "$(DESTDIR)/$${i}" ] || $(MKDIR) $(DESTDIR)/$${i}; \
	done

$(eval $(call AC_BUILD3_FOOT,admin))

#------------------------------------
#
locale_BUILDDIR?=$(BUILDDIR2)/locale-$(APP_BUILD)
locale_DEF_localedef=I18NPATH=$(TOOLCHAIN_SYSROOT)/usr/share/i18n localedef
locale_localedef=$(locale_DEF_localedef) -i $1 -f $2 $(or $(3),$(1).$(2))
locale_localenames=C.UTF-8

$(locale_BUILDDIR)/C.UTF-8: | $(locale_BUILDDIR)
	$(call locale_localedef,POSIX,UTF-8,$@) || true "force successful"

$(locale_BUILDDIR)/%: | $(locale_BUILDDIR)
	$(call locale_localedef, \
	    $(word 1,$(subst .,$(SPACE),$(@:$(locale_BUILDDIR)/%=%))), \
		$(word 2,$(subst .,$(SPACE),$(@:$(locale_BUILDDIR)/%=%))), \
		$@)

$(locale_BUILDDIR):
	$(MKDIR) $@

locale_install: DESTDIR=$(BUILD_SYSROOT)
locale_install: $(addprefix $(locale_BUILDDIR)/,$(locale_localenames))
	[ -d $(DESTDIR)/usr/lib/locale ] || $(MKDIR) $(DESTDIR)/usr/lib/locale
	cd $(locale_BUILDDIR) && \
	  $(locale_DEF_localedef) --add-to-archive --replace --prefix=$(DESTDIR) \
	  $(subst $(locale_BUILDDIR)/,,$^)

#------------------------------------
# dep: openssl libnl
#
wlregdb_DIR?=$(PKGDIR2)/wireless-regdb
crda_DIR=$(PKGDIR2)/crda
crda_BUILDDIR=$(BUILDDIR2)/crda
crda_MAKEPARAM+=REG_BIN=$(wlregdb_DIR)/regulatory.bin PUBKEY_DIR=$(wlregdb_DIR) \
    PREFIX=/ CFLAGS="-I$(BUILD_SYSROOT)/include $(BUILD_CFLAGS2_$(APP_PLATFORM))" \
	LDFLAGS=-L$(BUILD_SYSROOT)/lib USE_OPENSSL=1 CC=$(CC)
crda_MAKE=$(BUILD_PKGCFG_ENV) $(MAKE) $(crda_MAKEPARAM) \
	$(crda_MAKEPARAM_$(APP_PLATFORM)) -C $(crda_BUILDDIR)

crda_defconfig $(crda_BUILDDIR)/Makefile:
	[ -d $(crda_BUILDDIR) ] || $(MKDIR) $(crda_BUILDDIR)
	$(CP) $(crda_DIR)/* $(wlregdb_DIR)/regulatory.bin $(wlregdb_DIR)/sforshee.key.pub.pem \
	$(crda_BUILDDIR)/

crda_distclean:
	$(RM) $(crda_BUILDDIR)

crda: $(crda_BUILDDIR)/Makefile
	. $(BUILDDIR)/pyenv/bin/activate && $(crda_MAKE)

#------------------------------------
# dep: ub ub_tools linux_dtbs bb dtc
# dep for bpi: linux_Image.gz
# dep for other platform: linux_bzImage
#
dist_DIR?=$(DESTDIR)

# reference from linux_dtbs
dist_DTINCDIR+=$(linux_DIR)/scripts/dtc/include-prefixes

dtbbasename=$(BUILDDIR)/dtbbasename-$(APP_PLATFORM)

ifneq ($(strip $(filter bpi,$(APP_ATTR))),)
dist_DTINCDIR+=$(linux_DIR)/arch/arm64/boot/dts/allwinner
dist_dts=$(PROJDIR)/linux-sun50i-a64-bananapi-m64.dts
dist_dtb=$(linux_BUILDDIR)/arch/arm64/boot/dts/allwinner/sun50i-a64-bananapi-m64.dtb
dist_loadaddr=0x40080000
dist_compaddr=0x44000000
dist_compsize=0xb000000
dist_kernaddr=0x40200000
dist_fdtaddr=0x4fa00000
dist_scraddr=0x4fc00000
dist_rdaddr=0x4ff00000
endif

dist dist_sd:
	$(MAKE) $(APP_PLATFORM)_$@

dist_strip_known_sh_pattern=\.sh \.pl \.py c_rehash ncursesw6-config alsaconf \
    $(addprefix usr/bin/,xtrace tzselect ldd sotruss catchsegv mtrace) \
	lib/firmware/.*
dist_strip_known_sh_pattern2=$(subst $(SPACE),|,$(sort $(subst $(COMMA),$(SPACE), \
    $(dist_strip_known_sh_pattern))))
dist_strip:
	@echo -e "$(ANSI_GREEN)Strip executable$(if $($(@)_log),; logfile: $($(@)_log))$(ANSI_NORMAL)"
	@if [ -n "$($(@)_log)" ] && [ ! -d $(dir $($(@)_log)) ]; then \
	  $(MKDIR) $(dir $($(@)_log)); \
	fi
	@$(if $($(@)_log),echo -e "\n$$(date)" >> $($(@)_log))
	@$(if $($(@)_log),echo "Strip start; path: $($(@)_DIR) $($(@)_EXTRA)" >> $($(@)_log))
	@for i in $(addprefix $($(@)_DIR), \
	    usr/lib/libgcc_s.so.1 usr/lib64/libgcc_s.so.1 \
	    bin sbin lib lib64 usr/bin usr/sbin usr/lib usr/lib64) \
	    $($(@)_EXTRA); do \
	  if [ ! -e "$$i" ]; then \
	    $(if $($(@)_log),echo "Skip explicite absent $$i" >> $($(@)_log);) \
	    continue; \
	  fi; \
	  [ -f "$$i" ] && { \
	    $(if $($(@)_log),echo "Strip explicite $$i" >> $($(@)_log);) \
	    $(STRIP) -g $$i; \
	    continue; \
	  }; \
	  [ -d "$$i" ] && { \
	    $(if $($(@)_log),echo "Strip recurse dir $$i" >> $($(@)_log);) \
	    for j in `find $$i`; do \
	      [[ "$$j" =~ .+($(dist_strip_known_sh_pattern2)) ]] && { \
	        $(if $($(@)_log),echo "Skip known script/file $$j" >> $($(@)_log);) \
	        continue; \
		  }; \
	      [[ "$$j" =~ .*/lib/modules/.+\.ko ]] && { \
	        $(if $($(@)_log),echo "Strip implicite kernel module $$j" >> $($(@)_log);) \
	        $(STRIP) -g $$j; \
	        continue; \
	      }; \
	      [ ! -x "$$j" ] && { \
	        $(if $($(@)_log),echo "Skip non-executable $$j" >> $($(@)_log);) \
	        continue; \
	      }; \
	      [ -L "$$j" ] && { \
	        $(if $($(@)_log),echo "Skip symbolic $$j (`readlink $$j`)" >> $($(@)_log);) \
	        continue; \
	      }; \
	      [ -d "$$j" ] && { \
	        $(if $($(@)_log),echo "Skip dirname $$j" >> $($(@)_log);) \
	        continue; \
	      }; \
	      $(if $($(@)_log),echo "Strip implicite file $$j" >> $($(@)_log);) \
	      $(STRIP) -g $$j; \
	    done; \
	  }; \
	done

dist_elfdep: elfdep_log=$(BUILDDIR)/elfdep_log-$(APP_PLATFORM).txt
dist_elfdep:
	@echo -e "$(ANSI_GREEN)ELF dep dump$(ANSI_NORMAL)"
	@echo "# `date`" $(if $(elfdep_log),&>> $(elfdep_log))
	for i in $(addprefix $(dist_DIR)/rootfs/, \
	    usr/lib/libgcc_s.so.1 usr/lib64/libgcc_s.so.1 \
	    bin sbin lib lib64 usr/bin usr/sbin usr/lib usr/lib64); do \
	  if [ ! -e "$$i" ]; then \
	    echo "# Skipping missing explicite $$i" $(if $(elfdep_log),&>> $(elfdep_log)); \
	    continue; \
	  fi; \
	  [ -f "$$i" ] && { \
	    echo "# ELF explicite $$i" $(if $(elfdep_log),&>> $(elfdep_log)); \
		$(call ELFDEP,"$$i") $(if $(elfdep_log),&>> $(elfdep_log)); \
	    continue; \
	  }; \
	  [ -d "$$i" ] && { \
	    echo "# Recurse dir $$i" $(if $(elfdep_log),&>> $(elfdep_log)); \
	    for j in `find $$i`; do \
	      [[ "$$j" =~ .+(\.sh|\.pl|\.py|c_rehash|ncursesw6-config|alsaconf) ]] && { \
	        echo "# Skip known script/file $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	        continue; \
	      }; \
	      [[ "$$j" =~ .*/lib/modules/.+\.ko ]] && { \
	        echo "# ELF implicite kernel module $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	        $(call ELFDEP,"$$j") $(if $(elfdep_log),&>> $(elfdep_log)); \
	        continue; \
	      }; \
	      [ ! -x "$$j" ] && { \
	        echo "# Skipping non-executable $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	        continue; \
	      }; \
	      [ -L "$$j" ] && { \
	        echo "# Skipping symbolic $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	        continue; \
	      }; \
	      [ -d "$$j" ] && { \
	        echo "# Skipping dirname $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	        continue; \
	      }; \
	      echo "# ELF implicite file $$j" $(if $(elfdep_log),&>> $(elfdep_log)); \
	      $(call ELFDEP,"$$j") $(if $(elfdep_log),&>> $(elfdep_log)); \
	    done; \
	  }; \
	done
	echo "" $(if $(elfdep_log),&>> $(elfdep_log))
	echo "# Sorted result" $(if $(elfdep_log),&>> $(elfdep_log))
	$(if $(elfdep_log), cat "$(elfdep_log)" | "grep" -v -e "^\s*#" -e "^\s*$$" \
	  | sort | uniq &>> $(elfdep_log))

dist_%:
	$(MAKE) $(APP_PLATFORM)_$@

DEPBUILD_%:
	$(MAKE) $(@:DEPBUILD_%=%)

DEPBUILD=$(addprefix DEPBUILD_,$(sort $(1))): $(addsuffix $(strip $(2)),$(addprefix DEPBUILD_,$(sort $(3))))
DEPBUILD2=$(call DEPBUILD,$(addsuffix $(strip $(2)),$(1)),$(2),$(3))

$(eval $(call DEPBUILD,ub,,$(ub_PKGDEP)))
$(eval $(call DEPBUILD,ub_envtools_install,,ub))
$(eval $(call DEPBUILD,linux_dtbs,,linux_Image.gz))
$(eval $(call DEPBUILD,linux_headers_install,,linux_dtbs))

$(foreach pkg,libacl libxml2 libtextstyle dbus libcap systemd avahi mtdutil \
    ethtool tmux alsautils ff iw hostapd wpasup \
    ,$(eval $(call DEPBUILD2,$(pkg),_dist_install,$($(pkg)_PKGDEP))))

ub20_dist:
	[ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_install
	$(MAKE) zlib_install libasound_install
	$(MAKE) ncursesw_install
	$(MAKE) libnl_install alsautils_install ff_dist_install openssl_install
	# $(MAKE) mdns_install iw_install
	$(MAKE) wpasup_install
	# $(MAKE) fdkaac_install

$(addsuffix _dist_dtb,bpi):
	@[ -d $(dist_DIR)/boot ] || $(MKDIR) $(dist_DIR)/boot
	if [ -f "$(dist_dts)" ]; then \
	  echo -e "$(ANSI_GREEN)Compile linux device tree$(ANSI_NORMAL)"; \
	  echo $(basename $(notdir $(dist_dts))) > $(dtbbasename) && \
	  $(call CPPDTS) $(addprefix -I,$(dist_DTINCDIR)) \
	      -o $(BUILDDIR)/$(notdir $(dist_dts)) $(dist_dts) && \
	  $(call DTC2) $(addprefix -i,$(dist_DTINCDIR)) \
	      -o $(dist_DIR)/boot/$$(cat $(dtbbasename)).dtb \
	      $(BUILDDIR)/$(notdir $(dist_dts)); \
	else \
	  echo $(basename $(notdir $(dist_dtb))) > $(dtbbasename); \
	fi
	@echo -e "$(ANSI_GREEN)Decompile linux device tree$(ANSI_NORMAL)"
	$(PROJDIR)/tool/bin/dtc -I dtb -O dts \
	    $(dist_DIR)/boot/$$(cat $(dtbbasename)).dtb \
	    > $(BUILDDIR)/$$(cat $(dtbbasename))-dec.dts
	@chmod 664 $(dist_DIR)/boot/$$(cat $(dtbbasename)).dtb

bpi_dist_initramfs: | $(kernelrelease)
	$(RM) $(BUILD_SYSROOT)/lib/modules
	[ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_dist_install
	[ -x $(PROJDIR)/tool/bin/dtc ] || $(MAKE) dtc_dist_install
	[ -x $(PROJDIR)/tool/bin/mkimage ] || $(MAKE) ub_tools_install
	$(MAKE) $(BUILDPARALLEL:%=-j%) atf_bl31 crust_scp linux_Image.gz
	$(MAKE) $(BUILDPARALLEL:%=-j%) ub linux_dtbs
	$(MAKE) $(BUILDPARALLEL:%=-j%) ub_envtools linux_modules
	$(MAKE) $(BUILDPARALLEL:%=-j%) ub_envtools_install linux_headers_install \
	    linux_modules_install zlib_dist_install
	[ -d $(dist_DIR)/boot ] || $(MKDIR) $(dist_DIR)/boot
	rsync -av $(ub_BUILDDIR)/u-boot-sunxi-with-spl.bin \
	    $(linux_BUILDDIR)/arch/arm64/boot/Image.gz $(dist_dtb) \
	    $(dist_DIR)/boot/
	$(MAKE) dist_dtb
	[ -d $(BUILDDIR)/initramfs ] || $(MKDIR) $(BUILDDIR)/initramfs
	cd $(TOOLCHAIN_SYSROOT) && \
	  rsync -avR --ignore-missing-args \
	      $(foreach i,audit/ gconv/ locale/ libasan.* libgfortran.* libubsan.* \
		    *.a *.o *.la,--exclude="${i}") \
	      lib lib64 usr/lib usr/lib64 \
	      $(BUILDDIR)/initramfs/
	cd $(TOOLCHAIN_SYSROOT) && \
	  rsync -avR --ignore-missing-args \
	      $(foreach i,sbin/sln usr/bin/gdbserver,--exclude="${i}") \
	      sbin usr/bin usr/sbin \
	      $(BUILDDIR)/initramfs/
	$(MAKE) DESTDIR=$(BUILDDIR)/initramfs bb_dist_install
	$(RSYNC) $(PROJDIR)/prebuilt/initramfs/common/* $(BUILDDIR)/initramfs/
	echo -n "" > $(BUILDDIR)/devlist
	echo "dir /dev 0755 0 0" >> $(BUILDDIR)/devlist
	echo "nod /dev/console 0600 0 0 c 5 1" >> $(BUILDDIR)/devlist
	echo "nod /dev/loop0 644 0 0 b 7 0" >> $(BUILDDIR)/devlist
	echo "dir /proc 755 0 0" >> $(BUILDDIR)/devlist
	echo "dir /sys 755 0 0" >> $(BUILDDIR)/devlist
	cd $(linux_BUILDDIR) && $(linux_DIR)/usr/gen_initramfs.sh \
	    -l $(BUILDDIR)/initramfs.d $(BUILDDIR)/devlist $(BUILDDIR)/initramfs \
	  | gzip -9 >$(dist_DIR)/initramfs.cpio.gz
	mkimage -n "initramfs" -A arm64 -O linux -T ramdisk -C gzip \
	    -d $(dist_DIR)/initramfs.cpio.gz $(dist_DIR)/uInitramfs

rootfs: ROOTFSDIR=$(dist_DIR)/rootfs
rootfs $(dist_DIR)/rootfs:
	@for i in dev proc root mnt media sys tmp var/run var/lock \
	    lib/firmware lib64 libx usr/lib usr/lib64 usr/libx; do \
	  [ -d $(or $(ROOTFSDIR),$@)/$$i ] || $(MKDIR) $(or $(ROOTFSDIR),$@)/$$i; \
	done

DIST_DEBUG_SYSTEMD=1
bpi_dist: | $(dist_DIR)/rootfs $(kernelrelease)
	if [ -z "$(dist_DIR)" ] || [ "$(abspath $(dist_DIR))" = "/" ]; then \
	  false "Invalid dist_DIR"; \
	fi
	@for prefix in $(BUILD_SYSROOT) $(dist_DIR)/rootfs; do \
	  $(RM) -v $${prefix}/lib/modules; \
	done
	@[ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_dist_install
	@[ -x $(PROJDIR)/tool/bin/dtc ] || $(MAKE) dtc_dist_install
	@[ -x $(PROJDIR)/tool/bin/mkimage ] || $(MAKE) ub_tools_install
	$(MAKE) $(BUILDPARALLEL:%=-j%) $(addprefix DEPBUILD_,ub_envtools_install \
	    linux_headers_install)
ifneq ($(strip $(DIST_DEBUG_SYSTEMD)),1)
	$(MAKE) $(BUILDPARALLEL:%=-j%) linux_modules
	$(MAKE) $(BUILDPARALLEL:%=-j%) linux_modules_install
endif
ifneq ($(strip $(DIST_DEBUG_SYSTEMD)),1)
	$(MAKE) $(BUILDPARALLEL:%=-j%) $(patsubst %,DEPBUILD_%_dist_install, \
	    mtdutil hostapd ff alsautils avahi)
endif
	$(MAKE) $(BUILDPARALLEL:%=-j%) $(patsubst %,DEPBUILD_%_dist_install, \
	    tmux ethtool wpasup iw systemd)
	$(MAKE) $(BUILDPARALLEL:%=-j%) bb_dist_install locale_install \
	    ncursesw_terminfo_dist_install
	@echo -e "$(ANSI_GREEN)Install booting files$(ANSI_NORMAL)"
	@[ -d $(dist_DIR)/boot ] || $(MKDIR) $(dist_DIR)/boot
	@rsync -av $(ub_BUILDDIR)/u-boot-sunxi-with-spl.bin \
	    $(linux_BUILDDIR)/arch/arm64/boot/Image.gz $(dist_dtb) \
	    $(dist_DIR)/boot/
	$(MAKE) $(@)_dtb
	@echo -e "$(ANSI_GREEN)Create uboot environment image$(ANSI_NORMAL)"
	@echo -n "" > $(BUILDDIR)/uboot.env.txt
	@echo "loadaddr=${dist_loadaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "kernel_comp_addr_r=${dist_compaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "kernel_comp_size=${dist_compsize}" >> $(BUILDDIR)/uboot.env.txt
	@echo "fdtaddr=${dist_fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "loadkernel=fatload mmc 0:1 \$${loadaddr} Image.gz" >> $(BUILDDIR)/uboot.env.txt
	@echo "loadfdt=fatload mmc 0:1 \$${fdtaddr} $$(cat $(dtbbasename)).dtb" >> $(BUILDDIR)/uboot.env.txt
	@echo "bootargs=console=ttyS0,115200n8 rootfstype=ext4,ext2 root=/dev/mmcblk2p2 rw rootwait" >> $(BUILDDIR)/uboot.env.txt
	@echo "bootcmd=run loadkernel; run loadfdt; booti \$${loadaddr} - \$${fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	@mkenvimage -s `sed -n -e "s/^\s*CONFIG_ENV_SIZE\s*=\s*\([0-9x]\)/\1/p" $(ub_BUILDDIR)/.config` \
	    `grep -e ^\s*CONFIG_SYS_REDUNDAND_ENVIRONMENT\s*=\s*y\s* $(ub_BUILDDIR)/.config > /dev/null && echo -n "-r"` \
		-o $(dist_DIR)/boot/uboot.env $(BUILDDIR)/uboot.env.txt
	@chmod 664 $(dist_DIR)/boot/uboot.env
	@echo -e "$(ANSI_GREEN)Start populate rootfs$(ANSI_NORMAL)"
	@for i in lib lib64 usr/lib usr/lib64; do \
	  cd $(TOOLCHAIN_SYSROOT) && rsync -av --ignore-missing-args \
	      $(foreach i,audit/ gconv/ locale/ libasan.* libgfortran.* libubsan.* \
	      	*.a *.o *.la,--exclude="${i}") \
	      $$i/* $(dist_DIR)/rootfs/$$i/; \
	done
	@cd $(TOOLCHAIN_SYSROOT) && rsync -avR --ignore-missing-args \
	    $(foreach i,sbin/sln usr/bin/gdbserver,--exclude="${i}") \
	    sbin usr/bin usr/sbin $(dist_DIR)/rootfs/
	for i in lib lib64 usr/lib usr/lib64; do \
	  [ -e $(BUILD_SYSROOT)/$$i ] || continue; \
	  cd $(BUILD_SYSROOT) && rsync -av --ignore-missing-args \
	      --exclude="*.a" --exclude="*.la" --exclude="*.o" \
	      $$i/* $(dist_DIR)/rootfs/$$i/; \
	done
	@cd $(BUILD_SYSROOT) && rsync -avR --ignore-missing-args \
	    $(foreach i,bin/amidi etc/xattr.conf share/aclocal share/doc \
	    share/ffmpeg share/locale share/man share/sounds,--exclude="${i}") \
	    etc bin sbin share usr/bin usr/sbin usr/share var linuxrc $(dist_DIR)/rootfs/
	@rsync -av $(wlregdb_DIR)/regulatory.db $(wlregdb_DIR)/regulatory.db.p7s \
	    $(dist_DIR)/rootfs/lib/firmware/
	$(MAKE) DESTDIR=$(dist_DIR)/rootfs ap6212_install
ifneq ($(strip $(filter ath9k_htc,$(APP_ATTR))),)
	$(MAKE) DESTDIR=$(dist_DIR)/rootfs ath9k_install
endif
	@$(MAKE) dist_strip_DIR=$(dist_DIR)/rootfs/ dist_strip_log=$(dist_log) \
	    dist_strip
	@echo -e "$(ANSI_GREEN)Install prebuilt$(ANSI_NORMAL)"
	@rsync -av -I $(wildcard $(PROJDIR)/prebuilt/common/*) \
	    $(dist_DIR)/rootfs/
	@rsync -av -I $(wildcard $(PROJDIR)/prebuilt/$(APP_PLATFORM)/common/*) \
	    $(dist_DIR)/rootfs/
	$(CP) $(dist_DIR)/rootfs/etc/skel/.profile $(dist_DIR)/rootfs/etc/skel/.exrc \
	    $(dist_DIR)/rootfs/etc/skel/.tmux.conf \
	    $(dist_DIR)/rootfs/root/
	ln -sf /var/run/udhcpc/resolv.conf $(dist_DIR)/rootfs/etc/resolv.conf
	ln -sf /var/run/ld.so.cache $(dist_DIR)/rootfs/etc/ld.so.cache
	@if [ -e "$(dist_DIR)/rootfs/lib/modules/$$(cat $(kernelrelease))" ]; then \
	  echo -e "$(ANSI_GREEN)Generate kernel module dependencies$(ANSI_NORMAL)"; \
	  $(bb_DIR)/examples/depmod.pl \
	      -b "$(dist_DIR)/rootfs/lib/modules/$$(cat $(kernelrelease))" \
	      -F $(linux_BUILDDIR)/System.map; \
	else \
	  echo -e "$(ANSI_GREEN)Skip generate kernel module dependencies$(ANSI_NORMAL)"; \
	fi
	$(MAKE) $(APP_PLATFORM)_dist_systemdinit

bpi_dist_systemdinit:
	if [ ! -f $(dist_DIR)/rootfs/lib/systemd/systemd ]; then \
	  false "No systemd"; \
	fi
	$(RM) $(dist_DIR)/rootfs/sbin/init
	ln -sf ../lib/systemd/systemd $(dist_DIR)/rootfs/sbin/init

# sudo dd if=$(dist_DIR)/boot/u-boot-sunxi-with-spl.bin of=/dev/sdxxx bs=1024 seek=8
bpi_dist_sd:
	rsync -av $(dist_DIR)/boot/* /media/$(USER)/BOOT/
	rsync -av $(dist_DIR)/rootfs/* /media/$(USER)/rootfs/
	sync; sync

xm_dist: dist_DTINCDIR+=$(linux_DIR)/arch/arm/boot/dts
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
	#   setenv bootargs console=ttyS2,115200n8 root=/dev/mmcblk0p2 rw rootwait; \
	#   setenv loadaddr 0x81000000; setenv fdtaddr 0x82000000; \
	#   fatload mmc 0:1 ${loadaddr} /zImage; fatload mmc 0:1 ${fdtaddr} /omap3-beagle-xm-ab.dtb; bootz ${loadaddr} - ${fdtaddr}; \
	# EOFF

xm_dist_sd:
	$(CP) $(dist_DIR)/boot/* /media/$(USER)/BOOT/
	$(CP) $(BUILD_SYSROOT)/* /media/$(USER)/rootfs/

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
	@echo -n "" >  $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "setenv bootargs console=ttyS2,115200n8 root=/dev/ram0" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "setenv loadaddr $(xm_boot_linux_LOADADDR)" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "setenv fdtaddr $(xm_boot_dtb_LOADADDR)" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "setenv rdaddr $(xm_boot_initramfs_LOADADDR)" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "fatload mmc 0:1 \$${loadaddr} /boot/uImage" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "fatload mmc 0:1 \$${fdtaddr} /boot/omap3-beagle-xm-ab.dtb" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "setenv initrd_high 0xffffffff" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "fatload mmc 0:1 \$${rdaddr} /boot/uInitramfs" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "bootm \$${loadaddr} \$${rdaddr} \$${fdtaddr}" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	@echo "bootm \$${loadaddr} - \$${fdtaddr}" \
	  | tee -a $(BUILDDIR)/$(APP_PLATFORM)_boot.sh
	mkimage -n "boot script" -A arm -O linux -T script -C none \
	  -d $(BUILDDIR)/$(APP_PLATFORM)_boot.sh $(DESTDIR_BOOT)/boot.scr
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

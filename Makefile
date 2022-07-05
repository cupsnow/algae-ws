#------------------------------------
#
PROJDIR?=$(abspath $(firstword $(wildcard ./builder ../builder))/..)
-include $(PROJDIR:%=%/)builder/site.mk
include $(PROJDIR:%=%/)builder/proj.mk

.DEFAULT_GOAL=help
SHELL=/bin/bash

BUILDPARALLEL?=$(shell nproc)

BUILDDIR2=$(abspath $(PROJDIR)/../build)
PKGDIR2=$(abspath $(PROJDIR)/..)

# ath9k_htc
APP_ATTR_xm?=xm ath9k_htc
APP_ATTR_bpi?=bpi ath9k_htc
APP_ATTR_ub20?=ub20
export APP_ATTR?=$(APP_ATTR_bpi)

APP_PLATFORM=$(strip $(filter xm bpi ub20,$(APP_ATTR)))
ifneq ("$(strip $(filter xm,$(APP_PLATFORM)))","")
APP_BUILD=arm
else ifneq ("$(strip $(filter bpi,$(APP_PLATFORM)))","")
APP_BUILD=aarch64
else
APP_BUILD=$(APP_PLATFORM)
endif

ifneq ("$(strip $(filter xm,$(APP_ATTR)))","")
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/gcc-arm-none-linux-gnueabihf))
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin)
else ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/gcc-aarch64-none-linux-gnu))
$(eval $(call DECL_TOOLCHAIN_GCC,$(HOME)/07_sw/or1k-linux-musl,OR1K))
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin) $(OR1K_TOOLCHAIN_PATH:%=%/bin)
else ifneq ("$(strip $(filter ub20,$(APP_PLATFORM)))","")
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

# $(info Makefile ... Variable summary:$(NEWLINE) \
#     $(EMPTY) APP_ATTR: $(APP_ATTR), APP_PLATFORM: $(APP_PLATFORM)$(NEWLINE) \
#     $(EMPTY) TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT)$(NEWLINE) \
#     $(EMPTY) OR1K_TOOLCHAIN_SYSROOT: $(OR1K_TOOLCHAIN_SYSROOT)$(NEWLINE) \
#     $(EMPTY) PATH=$(PATH))

#------------------------------------
#
run_help_color=echo -e "Color demo: $(strip $(foreach i, \
    RED GREEN BLUE CYAN YELLOW MAGENTA, \
    $(ANSI_$(i))$(i))$(ANSI_NORMAL))"
help:
	@$(run_help_color)
	@echo "APP_ATTR: $(APP_ATTR)"
	@echo "TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT)"
ifneq ("$(strip $(V))",)
	$(BUILD_PKGCFG_ENV) pkg-config --list-all
endif

var_%:
	@echo "$(strip $($(@:var_%=%)))"

#------------------------------------
# dep: apt install dvipng imagemagick plantuml
#
pyenv $(BUILDDIR)/pyenv:
	virtualenv -p python3 $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  python --version && \
	  pip install -r requirements.txt

pyenv2 $(BUILDDIR)/pyenv2:
	virtualenv -p python2 $(BUILDDIR)/pyenv2
	. $(BUILDDIR)/pyenv2/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six

#------------------------------------
# sunxi-tools v1.1-487-g6c02224
# dep: dtc
#
sunxitools_DIR=$(PKGDIR2)/sunxi-tools
sunxitools_BUILDDIR=$(BUILDDIR2)/sunxitools-host
sunxitools_CFLAGS=-I$(PROJDIR)/tool/include -L$(PROJDIR)/tool/lib
sunxitools_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) \
    CFLAGS="$(sunxitools_CFLAGS)" DESTDIR=$(DESTDIR) PREFIX= \
    -C $(sunxitools_BUILDDIR)

sunxitools_defconfig $(sunxitools_BUILDDIR)/Makefile:
	git clone $(sunxitools_DIR) $(sunxitools_BUILDDIR)

sunxitools_install: DESTDIR=$(PROJDIR)/tool

sunxitools: $(sunxitools_BUILDDIR)/Makefile
	$(sunxitools_MAKE)

sunxitools_%: $(sunxitools_BUILDDIR)/Makefile
	$(sunxitools_MAKE) $(@:sunxitools_%=%)

#------------------------------------
# Device Tree Compiler v1.1-487-g6c02224
#
dtc_DIR?=$(PKGDIR2)/dtc
dtc_BUILDDIR?=$(BUILDDIR2)/dtc-host
dtc_MAKE=$(MAKE) PREFIX= DESTDIR=$(DESTDIR) NO_PYTHON=1 -C $(dtc_BUILDDIR)
# dtc_MAKE+=V=1

dtc_defconfig $(dtc_BUILDDIR)/Makefile:
	git clone $(dtc_DIR) $(dtc_BUILDDIR)

dtc_distclean:
	$(RM) $(dtc_BUILDDIR)

dtc_install: DESTDIR=$(PROJDIR)/tool

dtc_dist_install: DESTDIR=$(PROJDIR)/tool
dtc_dist_install:
	$(RM) $(dtc_BUILDDIR)_footprint
	echo "NO_PYTHON=1" > $(dtc_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,dtc,$(dtc_BUILDDIR)/Makefile)

dtc: $(dtc_BUILDDIR)/Makefile
	$(dtc_MAKE)

dtc_%: $(dtc_BUILDDIR)/Makefile
	$(dtc_MAKE) $(@:dtc_%=%)

#------------------------------------
# ARM Trusted Firmware-A v2.5-294-gabde216dc
# for bpi
#   make atf_bl31
#
atf_DIR?=$(PKGDIR2)/atf
atf_BUILDDIR?=$(BUILDDIR2)/atf-$(APP_PLATFORM)
atf_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) DEBUG=1 \
    BUILD_BASE=$(atf_BUILDDIR)
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
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

# atf:
# 	$(atf_MAKE)

atf_%:
	$(atf_MAKE) $(@:atf_%=%)

#------------------------------------
# Crust: Libre SCP firmware for Allwinner sunxi SoCs v0.4-5-gcff057d
# for bpi
#   make crust_scp
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

# crust: $(crust_BUILDDIR)/.config
# 	$(crust_MAKE)

crust_%: $(crust_BUILDDIR)/.config
	$(crust_MAKE) $(@:crust_%=%)

#------------------------------------
# u-boot v2021.10-rc1-269-g8f07f5376a
# ub_tools-only_defconfig ub_tools-only
# dep for bpi: atf_bl31, crust_scp
#
ub_DIR?=$(PKGDIR2)/uboot
ub_BUILDDIR?=$(BUILDDIR2)/uboot-$(APP_PLATFORM)
ub_DEF_MAKE?=$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
    KBUILD_OUTPUT=$(ub_BUILDDIR) CONFIG_TOOLS_DEBUG=1
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
ub_DEF_MAKE+=BL31=$(atf_BUILDDIR)/sun50i_a64/debug/bl31.bin \
    SCP=$(or $(wildcard $(crust_BUILDDIR)/scp/scp.bin),/dev/null)
endif
ub_MAKE=$(ub_DEF_MAKE) -C $(ub_BUILDDIR)
# ub_env_size=$(shell echo "$$(( $$(sed -n -e "s/^\s*CONFIG_ENV_SIZE\s*=\s*\([0-9x]\)/\1/p" $(ub_BUILDDIR)/.config) ))")
# ub_env_redundand=$(shell grep -e "^\s*CONFIG_SYS_REDUNDAND_ENVIRONMENT\s*=\s*y\s*" $(ub_BUILDDIR)/.config > /dev/null && echo "-r")

# return size if found
ub_env_size_cmd=sed -n -e s/^\s*CONFIG_ENV_SIZE\s*=\s*\([0-9x]\)/\1/p $(ub_BUILDDIR)/.config

# return 0 if found
ub_env_redundand_cmd=grep -e ^\s*CONFIG_SYS_REDUNDAND_ENVIRONMENT\s*=\s*y\s* $(ub_BUILDDIR)/.config

ub_mrproper ub_help:
	$(ub_DEF_MAKE) -C $(ub_DIR) $(@:ub_%=%)

# failed to build out-of-tree as of -f for linux
APP_PLATFORM_ub_defconfig:
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(ub_BUILDDIR) && \
	  $(CP) -v $(DOTCFG) $(ub_BUILDDIR)/.config && \
	  yes "" | $(ub_DEF_MAKE) -C $(ub_DIR) oldconfig; \
	else \
	  $(ub_DEF_MAKE) -C $(ub_DIR) $(DEFCFG); \
	fi

bpi_ub_defconfig: DOTCFG=$(PROJDIR)/uboot_bananapi_m64.config
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

ub: $(ub_BUILDDIR)/.config
	$(ub_MAKE)

ub_%: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(@:ub_%=%)

.NOTPARALLEL: ub ub_%

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
	  $(CP) -v $(DOTCFG) $(linux_BUILDDIR)/.config && \
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

linux: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(BUILDPARALLEL:%=-j%)

linux_%: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(BUILDPARALLEL:%=-j%) $(@:linux_%=%)

# .NOTPARALLEL: linux linux_%

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

ifneq ("$(strip $(filter ub20,$(APP_ATTR)))","")
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
libasound_CFGPARAM_$(APP_PLATFORM)+=--disable-topology
$(eval $(call AC_BUILD3_HEAD,libasound $(PKGDIR2)/alsa-lib $(BUILDDIR2)/libasound-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,libasound))

$(libasound_BUILDDIR)_footprint:
	echo "--disable-topology" > $(libasound_BUILDDIR)_footprint

$(eval $(call AC_BUILD3_DIST_INSTALL,libasound))
$(eval $(call AC_BUILD3_DISTCLEAN,libasound))
$(eval $(call AC_BUILD3_FOOT,libasound))

#------------------------------------
#
zlib_DIR=$(PKGDIR2)/zlib
zlib_BUILDDIR=$(BUILDDIR2)/zlib-$(APP_BUILD)
zlib_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(zlib_BUILDDIR)

zlib_configure $(zlib_BUILDDIR)/configure.log:
	[ -d "$(zlib_BUILDDIR)" ] || \
	  git clone $(zlib_DIR) $(zlib_BUILDDIR)
	cd $(zlib_BUILDDIR) && \
	  prefix= CROSS_PREFIX=$(CROSS_COMPILE) CFLAGS="-fPIC" ./configure

zlib_distclean:
	$(RM) $(zlib_BUILDDIR)

zlib_install: DESTDIR=$(BUILD_SYSROOT)

zlib_dist_install: DESTDIR=$(BUILD_SYSROOT)
zlib_dist_install:
	echo "-fPIC" > $(zlib_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,zlib,$(zlib_BUILDDIR)/configure.log)

zlib: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE)

zlib_%: $(zlib_BUILDDIR)/configure.log
	$(zlib_MAKE) $(patsubst _%,%,$(@:zlib%=%))

#------------------------------------
#
$(eval $(call AC_BUILD2,attr $(PKGDIR2)/attr $(BUILDDIR2)/attr-$(APP_BUILD)))

#------------------------------------
# dep: attr
#
$(eval $(call AC_BUILD2,acl $(PKGDIR2)/acl $(BUILDDIR2)/acl-$(APP_BUILD)))

#------------------------------------
#
lzo_CFGPARAM_$(APP_PLATFORM)+=--enable-shared

$(eval $(call AC_BUILD3_HEAD,lzo $(PKGDIR2)/lzo $(BUILDDIR2)/lzo-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,lzo))

$(lzo_BUILDDIR)_footprint:
	echo "--enable-shared" > $@

$(eval $(call AC_BUILD3_DIST_INSTALL,lzo))
$(eval $(call AC_BUILD3_DISTCLEAN,lzo))
$(eval $(call AC_BUILD3_FOOT,lzo))

#------------------------------------
#
e2fsprogs_CFGPARAM_$(APP_PLATFORM)+=$(addprefix --enable-,subset libuuid)

$(eval $(call AC_BUILD3_HEAD,e2fsprogs $(PKGDIR2)/e2fsprogs $(BUILDDIR2)/e2fsprogs-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,e2fsprogs))

$(e2fsprogs_BUILDDIR)_footprint:
	echo "$(addprefix --enable-,subset libuuid)" > $@

$(eval $(call AC_BUILD3_DIST_INSTALL,e2fsprogs))
$(eval $(call AC_BUILD3_DISTCLEAN,e2fsprogs))
$(eval $(call AC_BUILD3_FOOT,e2fsprogs))

#------------------------------------
# ubifs dep: lzo zlib uuid (e2fsprogs)
# jfss2 dep: acl zlib
#
mtdutil_CFGPARAM_$(APP_PLATFORM)+=--without-zstd

$(eval $(call AC_BUILD3_HEAD,mtdutil $(PKGDIR2)/mtd-utils $(BUILDDIR2)/mtdutil-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,mtdutil))

$(mtdutil_BUILDDIR)_footprint:
	echo "--without-zstd" > $@

$(eval $(call AC_BUILD3_DIST_INSTALL,mtdutil))
$(eval $(call AC_BUILD3_DISTCLEAN,mtdutil))
$(eval $(call AC_BUILD3_FOOT,mtdutil))

#------------------------------------
#
$(eval $(call AC_BUILD2,fdkaac $(PKGDIR2)/fdk-aac $(BUILDDIR2)/fdkaac-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,faad2 $(PKGDIR2)/faad2 $(BUILDDIR2)/faad2-$(APP_BUILD)))

#------------------------------------
#
ncursesw_DIR=$(PKGDIR2)/ncurses
ncursesw_BUILDDIR=$(BUILDDIR2)/ncursesw-$(APP_BUILD)
ncursesw_TINFODIR=/usr/share/terminfo

# refine to comma saperated list when use in tic
ncursesw_TINFO=ansi ansi-m color_xterm,linux,pcansi-m,rxvt-basic,vt52,vt100 \
  vt102,vt220,xterm,tmux-256color,screen-256color,xterm-256color

ncursesw_DEF_CFG=$(ncursesw_DIR)/configure --prefix= --with-shared \
  --with-termlib --with-ticlib --enable-widec --enable-pc-files \
  --with-default-terminfo-dir=$(ncursesw_TINFODIR)
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
	echo "$(ncursesw_DEF_CFG) --with-pkg-config=/lib" > $(ncursesw_BUILDDIR)_footprint
	if ! md5sum -c "$(ncursesw_BUILDDIR).md5sum"; then \
	  $(MAKE) DESTDIR=$(ncursesw_BUILDDIR)_destdir \
	      ncursesw_host_install && \
	  tar -cvf $(ncursesw_BUILDDIR).tar -C $(dir $(ncursesw_BUILDDIR)_destdir) \
	      $(notdir $(ncursesw_BUILDDIR)_destdir) && \
	  md5sum $(ncursesw_BUILDDIR).tar $(wildcard $(ncursesw_BUILDDIR)_footprint) $(ncursesw_BUILDDIR)/Makefile \
	      > $(ncursesw_BUILDDIR).md5sum && \
	  $(RM) $(ncursesw_BUILDDIR)_destdir; \
	fi
	[ -d "$(DESTDIR)" ] || $(MKDIR) $(DESTDIR)
	tar -xvf $(ncursesw_BUILDDIR).tar --strip-components=1 -C $(DESTDIR)

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

ncursesw_terminfo_dist_install: DESTDIR=$(PROJDIR)/tool
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
$(eval $(call AC_BUILD2,libmnl $(PKGDIR2)/libmnl $(BUILDDIR2)/libmnl-$(APP_BUILD)))

#------------------------------------
#
ethtool_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
ethtool_CFGPARAM_LDFLAGS_$(APP_PLATFORM)+=-lmnl
ethtool_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD2,ethtool $(PKGDIR2)/ethtool $(BUILDDIR2)/ethtool-$(APP_BUILD)))


#------------------------------------
#
openssl_DIR=$(PKGDIR2)/openssl
openssl_BUILDDIR=$(BUILDDIR2)/openssl-$(APP_BUILD)
openssl_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(openssl_BUILDDIR)

ifneq ("$(strip $(filter ub20 bpi,$(APP_ATTR)))","")
openssl_CFGPARAM_$(APP_PLATFORM)+=linux-generic64
else
openssl_CFGPARAM_$(APP_PLATFORM)+=linux-generic32
endif

openssl_defconfig $(openssl_BUILDDIR)/configdata.pm:
	[ -d $(openssl_BUILDDIR) ] || $(MKDIR) $(openssl_BUILDDIR)
	cd $(openssl_BUILDDIR) && \
	  $(openssl_DIR)/Configure $(openssl_CFGPARAM_$(APP_PLATFORM)) \
	    --cross-compile-prefix=$(CROSS_COMPILE) --prefix=/ \
	    --openssldir=/lib/ssl no-tests \
		-L$(BUILD_SYSROOT)/lib -I$(BUILD_SYSROOT)/include

openssl_install: DESTDIR=$(BUILD_SYSROOT)
openssl_install: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) install_sw install_ssldirs

openssl_dist_install: DESTDIR=$(BUILD_SYSROOT)
openssl_dist_install:
	echo "openssl_CFGPARAM_$(APP_PLATFORM) --openssldir=/lib/ssl" > $(openssl_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,openssl,$(openssl_BUILDDIR)/configdata.pm)

openssl: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE)

openssl_%: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) $(@:openssl_%=%)

#------------------------------------
#
libevent_CFGPARAM_$(APP_PLATFORM)+=--disable-openssl

$(eval $(call AC_BUILD3_HEAD,libevent $(PKGDIR2)/libevent $(BUILDDIR2)/libevent-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,libevent))

$(libevent_BUILDDIR)_footprint:
	echo "--disable-openssl" > $@

$(eval $(call AC_BUILD3_DIST_INSTALL,libevent))
$(eval $(call AC_BUILD3_DISTCLEAN,libevent))
$(eval $(call AC_BUILD3_FOOT,libevent))

#------------------------------------
# dep ncursesw libevent
#
tmux_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
tmux_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD2,tmux $(PKGDIR2)/tmux $(BUILDDIR2)/tmux-$(APP_BUILD)))

#------------------------------------
# dep: make libasound_install ncursesw_install
#
alsautils_CFGPARAM_$(APP_PLATFORM)+=--disable-alsatest
alsautils_CFGPARAM_CPPFLAGS_$(APP_PLATFORM)+=-I$(BUILD_SYSROOT)/include/ncursesw
alsautils_CFGENV_$(APP_PLATFORM)+=$(BUILD_PKGCFG_ENV)

$(eval $(call AC_BUILD3_HEAD,alsautils $(PKGDIR2)/alsa-utils $(BUILDDIR2)/alsautils-$(APP_BUILD)))
$(eval $(call AC_BUILD3_DEFCONFIG,alsautils))

$(alsautils_BUILDDIR)_footprint:
	echo "--disable-alsatest" > $@

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
# dep: zlib libasound_install ncursesw_install
#
ff_DIR=$(PKGDIR2)/ffmpeg
ff_BUILDDIR=$(BUILDDIR2)/ffmpeg-$(APP_PLATFORM)
ff_INCDIR=$(BUILD_SYSROOT)/include $(BUILD_SYSROOT)/include/ncursesw
ff_LIBDIR+=$(BUILD_SYSROOT)/lib64 $(BUILD_SYSROOT)/usr/lib64 \
  $(BUILD_SYSROOT)/lib $(BUILD_SYSROOT)/usr/lib
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
ff_CFGPARAM+=--arch=aarch64
else ifneq ("$(strip $(filter xm,$(APP_ATTR)))","")
ff_CFGPARAM+=--arch=arm --cpu=cortex-a5 --enable-vfpv3
else
ff_CFGPARAM+=--enable-debug=
endif

ff_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(ff_BUILDDIR)

APP_PLATFORM_ff_defconfig:
	[ -d "$(ff_BUILDDIR)" ] || $(MKDIR) $(ff_BUILDDIR)
	cd $(ff_BUILDDIR) && \
	  $(BUILD_PKGCFG_ENV) LD_LIBRARY_PATH=$(PROJDIR)/tool/lib \
	    $(ff_DIR)/configure --target-os=linux --cross_prefix=$(CROSS_COMPILE) \
		--enable-cross-compile $(ff_CFGPARAM) \
		--prefix=/ --disable-iconv --enable-pic --enable-shared \
	    --enable-hardcoded-tables --enable-pthreads --enable-ffplay \
	    --extra-cflags="$(addprefix -I,$(ff_INCDIR)) -D_REENTRANT" \
	    --extra-ldflags="$(addprefix -L,$(ff_LIBDIR))"

xm_ff_defconfig: ff_CFGPARAM+=--arch=arm --cpu=cortex-a5 --enable-vfpv3
xm_ff_defconfig: APP_PLATFORM_ff_defconfig

bpi_ff_defconfig: ff_CFGPARAM+=--arch=aarch64
bpi_ff_defconfig: APP_PLATFORM_ff_defconfig

ub20_ff_defconfig: ff_CFGPARAM+=--enable-debug=
ub20_ff_defconfig: APP_PLATFORM_ff_defconfig

ff_defconfig $(ff_BUILDDIR)/config.h:
	$(MAKE) $(APP_PLATFORM)_ff_defconfig

ff_install: DESTDIR=$(BUILD_SYSROOT)

ff_dist_install: DESTDIR=$(BUILD_SYSROOT)
ff_dist_install:
	$(RM) $(ff_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,ff,$(ff_BUILDDIR)/config.h)

ff: $(ff_BUILDDIR)/config.h
	$(ff_MAKE)

ff_%: $(ff_BUILDDIR)/config.h
	$(ff_MAKE) $(@:ff_%=%)

#------------------------------------
# dep: libnl3
#
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
# dep: openssl, libnl, linux_headers
#
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

wpasup_dist_install: DESTDIR=$(BUILD_SYSROOT)
wpasup_dist_install:
	$(RM) $(wpasup_BUILDDIR)_footprint
	$(call RUN_DIST_INSTALL1,wpasup,$(wpasup_BUILDDIR)/wpa_supplicant/.config)

wpasup: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE)

wpasup_%: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE) $(@:wpasup_%=%)

#------------------------------------
#
mdns_DIR=$(PKGDIR2)/mDNSResponder
mdns_BUILDDIR=$(BUILDDIR2)/mdns-$(APP_BUILD)
mdns_CPPFLAGS_EXTRA+=-lgcc_s -Wno-expansion-to-defined -Wno-stringop-truncation \
  -Wno-address-of-packed-member -Wno-enum-conversion

# match airplay makefile
mdns_BUILDDIR2=build/destdir

mdns_MAKE=$(MAKE) os=linux CC=$(CC) LD=$(LD) ST=$(STRIP) \
  CFLAGS_PTHREAD=-pthread LINKOPTS_PTHREAD=-pthread \
  BUILDDIR=$(mdns_BUILDDIR2) OBJDIR=build \
  CPPFLAGS_EXTRA+="$(mdns_CPPFLAGS_EXTRA)" \
  INSTBASE=$(INSTBASE) -C $(mdns_BUILDDIR)/mDNSPosix

mdns_defconfig $(mdns_BUILDDIR)/mDNSPosix/Makefile:
	[ -d $(mdns_BUILDDIR) ] || $(MKDIR) $(mdns_BUILDDIR)
	$(CP) $(mdns_DIR)/* $(mdns_BUILDDIR)

# dep: mdns
mdns_install: INSTBASE=$(BUILD_SYSROOT)
mdns_install: mdns | $(mdns_BUILDDIR)/mDNSPosix/Makefile
	$(mdns_MAKE) InstalledLib InstalledClients
	[ -d $(INSTBASE)/sbin ] || $(MKDIR) $(INSTBASE)/sbin
	$(CP) $(mdns_BUILDDIR)/mDNSPosix/$(mdns_BUILDDIR2)/mdnsd \
	  $(INSTBASE)/sbin/
	[ -d $(INSTBASE)/bin ] || $(MKDIR) $(INSTBASE)/bin
	$(CP) $(mdns_BUILDDIR)/mDNSPosix/$(mdns_BUILDDIR2)/mDNSClientPosix \
	  $(mdns_BUILDDIR)/mDNSPosix/$(mdns_BUILDDIR2)/mDNSNetMonitor \
	  $(mdns_BUILDDIR)/mDNSPosix/$(mdns_BUILDDIR2)/mDNSResponderPosix \
	  $(INSTBASE)/bin/
	[ -d $(INSTBASE)/share/man/man8 ] || $(MKDIR) $(INSTBASE)/share/man/man8
	$(CP) $(mdns_BUILDDIR)/mDNSShared/mDNSResponder.8 \
	  $(INSTBASE)/share/man/man8/mdnsd.8
	[ -d $(INSTBASE)/share/man/man1 ] || $(MKDIR) $(INSTBASE)/share/man/man1
	$(CP) $(mdns_BUILDDIR)/mDNSShared/dns-sd.1 \
	  $(INSTBASE)/share/man/man1

mdns $(mdns_BUILDDIR)/mDNSPosix/$(mdns_BUILDDIR2)/mdnsd: | $(mdns_BUILDDIR)/mDNSPosix/Makefile
	$(mdns_MAKE)

mdns_%: | $(mdns_BUILDDIR)/mDNSPosix/Makefile
	$(mdns_MAKE) $(@:mdns_%=%)

#------------------------------------
#
fftest1_bindir?=/bin
fftest1_CFGPARAM_$(APP_PLATFORM)+=--bindir=$(fftest1_bindir)
#fftest1_CFGPARAM_$(APP_PLATFORM)+=CFLAGS="-O0"
fftest1_CFGPARAM_ub20+=--enable-debug DATA_PREFIX="./"

$(eval $(call AC_BUILD3_HEAD,fftest1 $(PROJDIR)/package/fftest1 $(BUILDDIR2)/fftest1-$(APP_BUILD)))

fftest1_distclean:
	$(RM) $(fftest1_BUILDDIR)
	if [ -x $(fftest1_DIR)/distclean.sh ]; then \
	  $(fftest1_DIR)/distclean.sh; \
	fi

#fftest1_install: fftest1_cgi_install

fftest1_cgi_install: DESTDIR=$(BUILD_SYSROOT)
fftest1_cgi_install:
	[ -d $(DESTDIR)/var/cgi-bin ] || $(MKDIR) $(DESTDIR)/var/cgi-bin
	for i in fftest1_fwupd.cgi; do \
	  [ -e $(DESTDIR)/var/cgi-bin/$${i} ] || ln -sf ../../$(fftest1_bindir)/fftest1-cgi $(DESTDIR)/var/cgi-bin/$${i}; \
	done

# DESTDIR=`pwd`/build/sysroot-ub20 LD_LIBRARY_PATH=`pwd`/build/sysroot-ub20/lib:`pwd`/build/sysroot-ub20/usr/lib build/sysroot-ub20/sbin/lighttpd -f `pwd`/build/sysroot-ub20/etc/lighttpd.conf -m `pwd`/build/sysroot-ub20/lib -D
fftest1_host: DESTDIR=$(BUILD_SYSROOT)
fftest1_host:
	[ -d "$(DESTDIR)/var/www" ] || $(MKDIR) $(DESTDIR)/var/www
	ln -sf $(fftest1_DIR)/test/fwupd.html $(DESTDIR)/var/www/
	[ -d "$(DESTDIR)/etc" ] || $(MKDIR) $(DESTDIR)/etc
	[ -e $(DESTDIR)/etc/lighttpd.conf ] || ln -sf $(fftest1_DIR)/test/lighttpd.conf $(DESTDIR)/etc/
	$(MAKE) fftest1_cgi_install
	[ -d "$(DESTDIR)/media" ] || $(MKDIR) $(DESTDIR)/media
	[ -e $(DESTDIR)/media/ota-host.tar.gz ] || ln -sf $(PROJDIR)/destdir/ota.tar.gz $(DESTDIR)/media/ota-host.tar.gz
	[ -e $(DESTDIR)/media/sa7715 ] || ln -sf $(PROJDIR) $(DESTDIR)/media/sa7715
	for i in var/run; do \
	  [ -d "$(DESTDIR)/$${i}" ] || $(MKDIR) $(DESTDIR)/$${i}; \
	done

fftest1_testenv: DESTDIR=$(fftest1_BUILDDIR)
fftest1_testenv:
	for i in media var/run var/cgi-bin; do \
	  [ -d "$(DESTDIR)/$${i}" ] || $(MKDIR) $(DESTDIR)/$${i}; \
	done
	for i in var/www lighttpd.conf run-lighttpd.sh; do \
	  [ -e $(DESTDIR)/$${i} ] || ln -sf $(fftest1_DIR)/test/$${i} $(DESTDIR)/$$(dirname $${i}); \
	done
	@echo "Install cgi"
	for i in fftest1_fwupd.cgi; do \
	  [ -e $(DESTDIR)/var/cgi-bin/$${i} ] || ln -sf $(DESTDIR)/fftest1-cgi $(DESTDIR)/var/cgi-bin/$${i}; \
	done
	$(RM) $(DESTDIR)/media/* $(DESTDIR)/var/run/*
ifneq ("$(strip $(filter ub20,$(APP_PLATFORM)))","")
	[ -e $(PROJDIR)/destdir/ota.tar.gz ] && $(CP) $(PROJDIR)/destdir/ota.tar.gz $(DESTDIR)/media/
endif

$(eval $(call AC_BUILD3_FOOT,fftest1))


#------------------------------------
#
locale_BUILDDIR=$(BUILDDIR2)/locale-$(APP_BUILD)
locale_localedef=I18NPATH=$(TOOLCHAIN_SYSROOT)/usr/share/i18n localedef
locale_def?=C.UTF-8

$(locale_BUILDDIR)/C.UTF-8: | $(locale_BUILDDIR)
	$(locale_localedef) -i POSIX -f UTF-8 $@ 2>/dev/null || true "force pass"

$(locale_BUILDDIR)/%: | $(locale_BUILDDIR)
	$(locale_localedef) -i $(word 1,$(subst ., ,$(@:$(locale_BUILDDIR)/%=%))) \
		-f $(word 2,$(subst ., ,$(@:$(locale_BUILDDIR)/%=%))) $@

$(locale_BUILDDIR):
	$(MKDIR) $(locale_BUILDDIR)

locale: DESTDIR=$(BUILD_SYSROOT)
locale: $(addprefix $(locale_BUILDDIR)/,$(locale_def))
	[ -d $(DESTDIR)/usr/lib/locale ] || $(MKDIR) $(DESTDIR)/usr/lib/locale
	cd $(locale_BUILDDIR) && \
	  $(locale_localedef) --add-to-archive --prefix=$(DESTDIR) --replace \
	    $(locale_def)

#------------------------------------
# dep: ub ub_tools linux_dtbs bb dtc
# dep for bpi: linux_Image.gz
# dep for other platform: linux_bzImage
#
dist_DIR?=$(DESTDIR)
wlregdb_DIR?=$(PKGDIR2)/wireless-regdb
ap6212_DIR=$(PROJDIR)/package/ap6212

# reference from linux_dtbs
dist_DTINCDIR+=$(linux_DIR)/scripts/dtc/include-prefixes

dist dist_sd:
	$(MAKE) $(APP_PLATFORM)_$@

dist_strip_known_sh_pattern=\.sh \.pl \.py c_rehash ncursesw6-config alsaconf \
    $(addprefix usr/bin/,xtrace tzselect ldd sotruss catchsegv mtrace) \
	lib/firmware/.*
dist_strip_known_sh_pattern2=$(subst $(SPACE),|,$(sort $(subst $(COMMA),$(SPACE), \
    $(dist_strip_known_sh_pattern))))
dist_strip:
	@echo -e "$(ANSI_GREEN)Strip executable$(if $($(@)_log),$(COMMA) log to $($(@)_log))$(ANSI_NORMAL)"
	@$(if $($(@)_log),echo "" >> $($(@)_log); date >> $($(@)_log))
	@$(if $($(@)_log),echo "Start strip; path: $($(@)_DIR) $($(@)_EXTRA)" >> $($(@)_log))
	@for i in $(addprefix $($(@)_DIR), \
	  usr/lib/libgcc_s.so.1 usr/lib64/libgcc_s.so.1 \
	  bin sbin lib lib64 usr/bin usr/sbin usr/lib usr/lib64) $($(@)_EXTRA); do \
	  if [ ! -e "$$i" ]; then \
	    $(if $($(@)_log),echo "Strip skipping missing explicite $$i" >> $($(@)_log);) \
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
	        $(if $($(@)_log),echo "Strip skipping non-executable $$j" >> $($(@)_log);) \
	        continue; \
	      }; \
	      [ -L "$$j" ] && { \
	        $(if $($(@)_log),echo "Strip skipping symbolic $$j -> `readlink $$j`" >> $($(@)_log);) \
	        continue; \
	      }; \
	      [ -d "$$j" ] && { \
	        $(if $($(@)_log),echo "Strip skipping dirname $$j" >> $($(@)_log);) \
	        continue; \
	      }; \
	      $(if $($(@)_log),echo "Strip implicite file $$j" >> $($(@)_log);) \
	      $(STRIP) -g $$j; \
	    done; \
	  }; \
	done

dist_%:
	$(MAKE) $(APP_PLATFORM)_$@

ub20_dist:
	[ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_install
	$(MAKE) zlib_install libasound_install
	$(MAKE) ncursesw_install
	$(MAKE) libnl_install alsautils_install ff_dist_install openssl_install
	# $(MAKE) mdns_install iw_install
	$(MAKE) wpasup_install
	# $(MAKE) fdkaac_install

bpi_dist: dist_DTINCDIR+=$(linux_DIR)/arch/arm64/boot/dts/allwinner
bpi_dist: dist_dts=$(PROJDIR)/linux-sun50i-a64-bananapi-m64.dts
bpi_dist: dist_dtb=$(linux_BUILDDIR)/arch/arm64/boot/dts/allwinner/sun50i-a64-bananapi-m64.dtb
bpi_dist: dist_loadaddr=0x40080000 # 0x40200000
bpi_dist: dist_compaddr=0x44000000
bpi_dist: dist_compsize=0xb000000
bpi_dist: dist_fdtaddr=0x4fa00000
bpi_dist: dist_log=$(BUILDDIR)/dist_log-$(APP_PLATFORM).txt
bpi_dist:
	[ -d $(dir $(dist_log)) ] || $(MKDIR) $(dir $(dist_log))
	@$(if $(dist_log),echo "" >> $(dist_log); date >> $(dist_log))
	[ -x $(PROJDIR)/tool/bin/tic ] || $(MAKE) ncursesw_host_dist_install
	[ -x $(PROJDIR)/tool/bin/mkimage ] || $(MAKE) ub_tools_install
	[ -x $(PROJDIR)/tool/bin/dtc ] || $(MAKE) dtc_dist_install
ifeq ("$(filter-out placeholder,$(NB))","")
	$(MAKE) atf_bl31 crust_scp
	$(MAKE) ub ub_envtools linux_Image.gz linux_dtbs linux_modules \
	    linux_headers_install
	@$(if $(dist_log),date >> $(dist_log); echo "Done build boot/kernel" >> $(dist_log))
endif
ifeq ("$(filter-out 2,$(NB))","")
	$(MAKE) linux_modules_install zlib_dist_install libasound_dist_install \
	    ncursesw_dist_install attr_dist_install
	$(MAKE) alsautils_dist_install ff_dist_install bb_dist_install \
	    openssl_install libnl_dist_install libmnl_dist_install \
		ethtool_dist_install acl_dist_install lzo_dist_install \
		e2fsprogs_dist_install fdkaac_dist_install
	$(MAKE) wpasup_dist_install iw_install mtdutil_dist_install \
	    ncursesw_terminfo_dist_install locale
	@$(if $(dist_log),date >> $(dist_log); echo "Done build package" >> $(dist_log))
endif
	@echo -e "$(ANSI_GREEN)Install booting files$(ANSI_NORMAL)"
	@[ -d $(dist_DIR)/boot ] || $(MKDIR) $(dist_DIR)/boot
	@rsync -avv $(ub_BUILDDIR)/u-boot-sunxi-with-spl.bin \
	    $(linux_BUILDDIR)/arch/arm64/boot/Image.gz $(dist_dtb) \
	    $(dist_DIR)/boot/ $(if $(dist_log),&>> $(dist_log))
	@if [ -f "$(dist_dts)" ]; then \
	  echo -e "$(ANSI_GREEN)Compile linux device tree$(ANSI_NORMAL)"; \
	  $(call CPPDTS) $(addprefix -I,$(dist_DTINCDIR)) \
	      -o $(BUILDDIR)/$(notdir $(dist_dts)) $(dist_dts) && \
	  $(call DTC2) $(addprefix -i,$(dist_DTINCDIR)) \
	      -o $(dist_DIR)/boot/$(basename $(notdir $(dist_dts))).dtb \
	      $(BUILDDIR)/$(notdir $(dist_dts)) && \
	  { $(PROJDIR)/tool/bin/dtc -I dtb -O dts \
	        $(dist_DIR)/boot/$(basename $(notdir $(dist_dts))).dtb \
	        > $(BUILDDIR)/$(basename $(notdir $(dist_dts)))-dec.dts; }; \
	fi
	@echo -e "$(ANSI_GREEN)Create uboot environment image$(ANSI_NORMAL)"
	@echo -n "" > $(BUILDDIR)/uboot.env.txt
	@echo "loadaddr=${dist_loadaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "kernel_comp_addr_r=${dist_compaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "kernel_comp_size=${dist_compsize}" >> $(BUILDDIR)/uboot.env.txt
	@echo "fdtaddr=${dist_fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	@echo "loadkernel=fatload mmc 0:1 \$${loadaddr} Image.gz" >> $(BUILDDIR)/uboot.env.txt
	@if [ -f "$(dist_dts)" ]; then \
	  echo "loadfdt=fatload mmc 0:1 \$${fdtaddr} $(basename $(notdir $(dist_dts))).dtb" >> $(BUILDDIR)/uboot.env.txt; \
	else \
	  echo "loadfdt=fatload mmc 0:1 \$${fdtaddr} $(basename $(notdir $(dist_dtb))).dtb" >> $(BUILDDIR)/uboot.env.txt; \
	fi
	@echo "bootargs=console=ttyS0,115200n8 rootfstype=ext4,ext2 root=/dev/mmcblk2p2 rw rootwait" >> $(BUILDDIR)/uboot.env.txt
	@echo "bootcmd=run loadkernel; run loadfdt; booti \$${loadaddr} - \$${fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	@mkenvimage -s `sed -n -e "s/^\s*CONFIG_ENV_SIZE\s*=\s*\([0-9x]\)/\1/p" $(ub_BUILDDIR)/.config` \
	    `grep -e ^\s*CONFIG_SYS_REDUNDAND_ENVIRONMENT\s*=\s*y\s* $(ub_BUILDDIR)/.config > /dev/null && echo -n "-r"` \
		-o $(dist_DIR)/boot/uboot.env $(BUILDDIR)/uboot.env.txt
	@echo -e "$(ANSI_GREEN)Install userland$(ANSI_NORMAL)"
	@$(if $(dist_log),echo "" >> $(dist_log); date >> $(dist_log))
	@$(if $(dist_log),echo "Start populate sysroot to rootfs" >> $(dist_log))
	@for i in dev proc root mnt sys tmp var/run; do \
	  [ -d $(dist_DIR)/rootfs/$$i ] || $(MKDIR) $(dist_DIR)/rootfs/$$i; \
	done
	@cd $(TOOLCHAIN_SYSROOT) && \
	  rsync -avvR --ignore-missing-args \
	      --exclude="gconv/" --exclude="*.a" --exclude="*.o" --exclude="*.la" \
		  --exclude="libasan.*" --exclude="libgfortran.*" \
	      lib lib64 sbin usr/lib usr/lib64 usr/bin usr/sbin \
		  $(dist_DIR)/rootfs/ $(if $(dist_log),&>> $(dist_log))
	@cd $(BUILD_SYSROOT) && \
	  rsync -avvR --ignore-missing-args \
		  --exclude="bin/amidi" --exclude="share/aclocal" --exclude="share/man" \
		  --exclude="share/sounds" --exclude="share/doc" --exclude="share/ffmpeg" \
	      --exclude="share/locale" \
	      etc bin sbin share usr/bin usr/sbin usr/share var linuxrc \
	      $(dist_DIR)/rootfs/ $(if $(dist_log),&>> $(dist_log))
	@cd $(BUILD_SYSROOT) && \
	  rsync -avvR --ignore-missing-args \
	      --exclude="*.a" --exclude="*.la" --exclude="*.o" \
		  lib lib64 usr/lib usr/lib64 \
	      $(dist_DIR)/rootfs/ $(if $(dist_log),&>> $(dist_log))
	@[ -d $(dist_DIR)/rootfs/lib/firmware ] || \
	  $(MKDIR) $(dist_DIR)/rootfs/lib/firmware
	@rsync -avv $(wlregdb_DIR)/regulatory.db $(wlregdb_DIR)/regulatory.db.p7s \
		$(dist_DIR)/rootfs/lib/firmware/ $(if $(dist_log),&>> $(dist_log))
	@[ -d $(dist_DIR)/rootfs/lib/firmware/brcm ] || \
	  $(MKDIR) $(dist_DIR)/rootfs/lib/firmware/brcm
	@rsync -avv $(ap6212_DIR)/bpi/fw_bcm43438a1.bin \
	    $(dist_DIR)/rootfs/lib/firmware/brcm/brcmfmac43430-sdio.bin \
		$(if $(dist_log),&>> $(dist_log))
	@rsync -avv $(ap6212_DIR)/bpi/nvram_ap6212.txt \
	    $(dist_DIR)/rootfs/lib/firmware/brcm/brcmfmac43430-sdio.txt \
		$(if $(dist_log),&>> $(dist_log))
	@rsync -avv $(ap6212_DIR)/bpi/bcm43438a1.hcd \
	    $(dist_DIR)/rootfs/lib/firmware/brcm/BCM43430A1.hcd \
		$(if $(dist_log),&>> $(dist_log))
ifneq ("$(strip $(filter ath9k_htc,$(APP_ATTR)))","")
	[ -d $(dist_DIR)/rootfs/lib/firmware/ath9k_htc ] || $(MKDIR) $(dist_DIR)/rootfs/lib/firmware/ath9k_htc
	@rsync -avv /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw \
	    $(dist_DIR)/rootfs/lib/firmware/ath9k_htc/ \
	    $(if $(dist_log),&>> $(dist_log))
endif
	@$(MAKE) dist_strip_DIR=$(dist_DIR)/rootfs/ dist_strip_log=$(dist_log) \
	    dist_strip
	@echo -e "$(ANSI_GREEN)Install prebuilt$(ANSI_NORMAL)"
	@rsync -avv $(wildcard $(PROJDIR)/prebuilt/common/* \
	    $(PROJDIR)/prebuilt/$(APP_PLATFORM)/common/*) \
	    $(dist_DIR)/rootfs/ $(if $(dist_log),&>> $(dist_log))
	@echo -e "$(ANSI_GREEN)Generate kernel module dependencies$(ANSI_NORMAL)"
	@$(bb_DIR)/examples/depmod.pl \
	    -b "$(dist_DIR)/rootfs/lib/modules/$(linux_kernelrelease)" \
	    -F $(linux_BUILDDIR)/System.map

# sudo dd if=$(dist_DIR)/boot/u-boot-sunxi-with-spl.bin of=/dev/sdxxx bs=1024 seek=8
bpi_dist_sd:
	rsync -avv $(dist_DIR)/boot/* /media/$(USER)/BOOT/
ifeq ("$(NB)","")
	rsync -avv $(dist_DIR)/rootfs/* /media/$(USER)/rootfs/
else
	rsync -avv \
	    --exclude="lib/modules" \
		$(dist_DIR)/rootfs/* /media/$(USER)/rootfs/
endif

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

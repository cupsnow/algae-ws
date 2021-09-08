#------------------------------------
#
PROJDIR?=$(abspath $(firstword $(wildcard ./builder ../builder))/..)
-include $(PROJDIR:%=%/)builder/site.mk
include $(PROJDIR:%=%/)builder/proj.mk

.DEFAULT_GOAL=help
SHELL=/bin/bash

APP_ATTR_xm?=xm
APP_ATTR_bpi?=bpi
export APP_ATTR?=$(APP_ATTR_bpi)

APP_PLATFORM=$(strip $(filter xm bpi,$(APP_ATTR)))

ifneq ("$(strip $(filter xm,$(APP_ATTR)))","")
TOOLCHAIN_PATH=$(HOME)/07_sw/gcc-arm-none-linux-gnueabihf
CROSS_COMPILE=$(shell $(TOOLCHAIN_PATH)/bin/*-gcc -dumpmachine)-
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin)
TOOLCHAIN_SYSROOT?=$(abspath $(shell PATH=$(call ENVPATH,$(EXTRA_PATH)) && \
  $(CC) -print-sysroot))
else ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
TOOLCHAIN_PATH=$(HOME)/07_sw/gcc-aarch64-none-linux-gnu
CROSS_COMPILE=$(shell $(TOOLCHAIN_PATH)/bin/*-gcc -dumpmachine)-
EXTRA_PATH+=$(TOOLCHAIN_PATH:%=%/bin)
TOOLCHAIN_SYSROOT?=$(abspath $(shell PATH=$(call ENVPATH,$(EXTRA_PATH)) && \
  $(CC) -print-sysroot))
OR1K_TOOLCHAIN_PATH=$(HOME)/07_sw/or1k-linux-musl
OR1K_CROSS_COMPILE=$(shell $(OR1K_TOOLCHAIN_PATH)/bin/*-gcc -dumpmachine)-
EXTRA_PATH+=$(OR1K_TOOLCHAIN_PATH:%=%/bin)
OR1K_TOOLCHAIN_SYSROOT?=$(abspath $(shell PATH=$(call ENVPATH,$(EXTRA_PATH)) && \
  $(OR1K_CROSS_COMPILE)gcc -print-sysroot))
endif

export PATH:=$(call ENVPATH,$(PROJDIR)/tool/bin $(EXTRA_PATH))

# $(info Makefile ... APP_ATTR: $(APP_ATTR), APP_PLATFORM: $(APP_PLATFORM) \
#   , TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT), OR1K_TOOLCHAIN_SYSROOT: $(OR1K_TOOLCHAIN_SYSROOT) \
#   , PATH=$(PATH))

#------------------------------------
#
help:
	$(CC) -dumpmachine
	$(OR1K_CROSS_COMPILE)gcc -dumpmachine
	echo "APP_ATTR: $(APP_ATTR), APP_PLATFORM: $(APP_PLATFORM) \
	  , TOOLCHAIN_SYSROOT: $(TOOLCHAIN_SYSROOT) \
	  , OR1K_TOOLCHAIN_SYSROOT: $(OR1K_TOOLCHAIN_SYSROOT)"

#------------------------------------
# dep: apt install dvipng imagemagick plantuml
#
pyenv $(BUILDDIR)/pyenv:
	virtualenv -p python3 $(BUILDDIR)/pyenv
	. $(BUILDDIR)/pyenv/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six \
	    sphinxcontrib-plantuml

pyenv2 $(BUILDDIR)/pyenv2:
	virtualenv -p python2 $(BUILDDIR)/pyenv2
	. $(BUILDDIR)/pyenv2/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six

#------------------------------------
# dep: dtc
#
sunxitools_DIR=$(PROJDIR)/package/sunxi-tools
sunxitools_BUILDDIR=$(BUILDDIR)/sunxitools
sunxitools_INCDIR=$(PROJDIR)/tool/include
sunxitools_LIBDIR=$(PROJDIR)/tool/lib

sunxitools_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) \
  CFLAGS="-I$(PROJDIR)/tool/include -L$(PROJDIR)/tool/lib" \
  DESTDIR=$(DESTDIR) PREFIX= -C $(sunxitools_BUILDDIR)

sunxitools_defconfig $(sunxitools_BUILDDIR)/Makefile:
	git clone depth=1 $(sunxitools_DIR) $(sunxitools_BUILDDIR)

sunxitools_install: DESTDIR=$(PROJDIR)/tool

sunxitools: $(sunxitools_BUILDDIR)/Makefile
	$(sunxitools_MAKE)

sunxitools_%: $(sunxitools_BUILDDIR)/Makefile
	$(sunxitools_MAKE) $(@:sunxitools_%=%)

#------------------------------------
#
dtc_DIR?=$(PROJDIR)/package/dtc
dtc_BUILDDIR?=$(BUILDDIR)/dtc
dtc_MAKE=$(MAKE) PREFIX= DESTDIR=$(DESTDIR) NO_PYTHON=1 -C $(dtc_BUILDDIR)
# dtc_MAKE+=V=1

$(dtc_BUILDDIR):
	git clone $(dtc_DIR) $@

dtc_distclean:
	$(RM) $(dtc_BUILDDIR)

dtc: $(dtc_BUILDDIR)
	$(dtc_MAKE)

dtc_install: DESTDIR=$(PROJDIR)/tool

dtc_%: $(dtc_BUILDDIR)
	$(dtc_MAKE) $(@:dtc_%=%)

#------------------------------------
# for bpi
#   make atf_bl31
#
atf_DIR?=$(PROJDIR)/package/atf
atf_BUILDDIR?=$(BUILDDIR)/atf
atf_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) \
  DEBUG=1 BUILD_BASE=$(atf_BUILDDIR)
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
# for bpi
#   make crust_scp
#
crust_DIR?=$(PROJDIR)/package/crust
crust_BUILDDIR?=$(BUILDDIR)/crust
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
# ub_tools-only_defconfig ub_tools-only
# dep for bpi: atf_bl31, crust_scp
#
ub_DIR?=$(PROJDIR)/package/uboot
ub_BUILDDIR?=$(BUILDDIR)/uboot
ub_DEF_MAKE?=$(MAKE) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
  KBUILD_OUTPUT=$(ub_BUILDDIR) CONFIG_TOOLS_DEBUG=1
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
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

# dep: apt install dvipng imagemagick
#      apt install texlive-latex-extra
#      pip install sphinx_rtd_theme six
ub_htmldocs: | $(BUILDDIR)/pyenv $(ub_BUILDDIR)/.config
ifeq ("$(NB)","")
	. $(BUILDDIR)/pyenv/bin/activate && \
	  $(ub_MAKE) htmldocs
endif
	tar -Jcvf $(BUILDDIR)/uboot-docs.tar.xz --show-transformed-names \
	  --transform="s/output/uboot-docs/" -C $(ub_BUILDDIR)/doc output

ub_tools_install: DESTDIR=$(PROJDIR)/tool
ub_tools_install: ub_tools
	[ -d $(DESTDIR)/bin ] || $(MKDIR) $(DESTDIR)/bin
	for i in dumpimage fdtgrep gen_eth_addr gen_ethaddr_crc \
	    mkenvimage mkimage proftool spl_size_limit; do \
	  $(CP) $(ub_BUILDDIR)/tools/$$i $(DESTDIR)/bin/; \
	done

ub: $(ub_BUILDDIR)/.config
	$(ub_MAKE)

ub_%: $(ub_BUILDDIR)/.config
	$(ub_MAKE) $(@:ub_%=%)

.NOTPARALLEL: ub ub_%

#------------------------------------
#
linux_DIR?=$(PROJDIR)/package/linux
linux_BUILDDIR?=$(BUILDDIR)/linux
linux_DEF_MAKE?=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) KBUILD_OUTPUT=$(linux_BUILDDIR) \
  INSTALL_HDR_PATH=$(INSTALL_HDR_PATH) INSTALL_MOD_PATH=$(INSTALL_MOD_PATH) \
  LOADADDR=$(LOADADDR) CONFIG_INITRAMFS_SOURCE="$(CONFIG_INITRAMFS_SOURCE)"
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
linux_DEF_MAKE+=ARCH=arm64
else
linux_DEF_MAKE+=ARCH=arm
endif
linux_MAKE=$(linux_DEF_MAKE) -C $(linux_BUILDDIR)
linux_RELSTR=$(shell PATH=$(PATH) && $(linux_MAKE) -s kernelrelease)
linux_VERSTR=$(shell PATH=$(PATH) && $(linux_MAKE) -s kernelversion)

linux_mrproper linux_help:
	$(linux_DEF_MAKE) -C $(linux_DIR) $(@:linux_%=%)

APP_PLATFORM_linux_defconfig:
	$(MAKE) linux_mrproper
	if [ -f "$(DOTCFG)" ]; then \
	  $(MKDIR) $(linux_BUILDDIR) && \
	  $(CP) -v $(DOTCFG) $(linux_BUILDDIR)/.config && \
	  yes "" | $(linux_MAKE) -f $(linux_DIR)/Makefile oldconfig; \
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
	tar -Jcvf $(BUILDDIR)/linux-docs.tar.xz \
	  --show-transformed-names \
	  --transform="s/output/linux-docs/" \
	  -C $(linux_BUILDDIR)/Documentation output

linux_modules_install: INSTALL_MOD_PATH=$(BUILDDIR)/sysroot

linux_headers_install: INSTALL_HDR_PATH=$(BUILDDIR)/sysroot

bpi_linux_LOADADDR?=0x40200000

xm_linux_LOADADDR?=0x81000000

linux_uImage: LOADADDR?=$(APP_PLATFORM)_linux_LOADADDR

linux: $(linux_BUILDDIR)/.config
	$(linux_MAKE)

linux_%: $(linux_BUILDDIR)/.config
	$(linux_MAKE) $(@:linux_%=%)

.NOTPARALLEL: linux linux_%

#------------------------------------
#
bb_DIR?=$(PROJDIR)/package/busybox
bb_BUILDDIR=$(BUILDDIR)/busybox
bb_DEF_MAKE=$(MAKE) CROSS_COMPILE=$(CROSS_COMPILE) \
  CONFIG_PREFIX=$(CONFIG_PREFIX)
bb_MAKE=$(bb_DEF_MAKE) KBUILD_OUTPUT=$(bb_BUILDDIR) \
  -C $(bb_BUILDDIR)

bb_mrproper bb_help:
	$(bb_DEF_MAKE) -C $(bb_DIR) $(@:bb_%=%)

bb_defconfig $(bb_BUILDDIR)/.config:
	$(MAKE) bb_mrproper
	[ -d "$(bb_BUILDDIR)" ] || $(MKDIR) $(bb_BUILDDIR)
	if [ -f $(PROJDIR)/busybox.config ]; then \
	  $(CP) $(PROJDIR)/busybox.config $(bb_BUILDDIR)/.config && \
	  $(bb_DEF_MAKE) KBUILD_OUTPUT=$(bb_BUILDDIR) -C $(bb_DIR) oldconfig; \
	else \
	  $(bb_DEF_MAKE) KBUILD_OUTPUT=$(bb_BUILDDIR) -C $(bb_DIR) defconfig; \
	fi

bb_distclean:
	$(RM) $(bb_BUILDDIR)

# dep: apt install docbook
bb_doc: | $(bb_BUILDDIR)/.config
ifeq ("$(NB)","")
	$(bb_MAKE) doc
endif
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
libasound_DIR=$(PROJDIR)/package/libasound
libasound_BUILDDIR=$(BUILDDIR)/libasound
libasound_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(libasound_BUILDDIR)

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
ncursesw_DIR=$(PROJDIR)/package/ncurses
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
alsautil_DIR=$(PROJDIR)/package/alsa-utils
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
ifneq ("$(strip $(filter bpi,$(APP_ATTR)))","")
ff_LIBDIR+=$(BUILDDIR)/sysroot/lib64
ff_CFGPARAM+=--arch=aarch64
else
ff_CFGPARAM+=--arch=arm --cpu=cortex-a5 --enable-vfpv3
endif

ff_configure $(ff_BUILDDIR)/Makefile:
	[ -d "$(ff_BUILDDIR)" ] || $(MKDIR) $(ff_BUILDDIR)
	cd $(ff_BUILDDIR) && PKG_CONFIG_PATH="$(BUILDDIR)/sysroot/lib/pkgconfig" \
	  $(ff_DIR)/configure --enable-cross-compile --target-os=linux \
	    --cross_prefix=$(CROSS_COMPILE) --prefix=/ $(ff_CFGPARAM) \
		--disable-iconv --enable-pic --enable-shared \
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
#
openssl_DIR=$(PROJDIR)/package/openssl
openssl_BUILDDIR=$(BUILDDIR)/openssl
openssl_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(openssl_BUILDDIR)

openssl_defconfig $(openssl_BUILDDIR)/configdata.pm:
	# if [ ! -d $(openssl_BUILDDIR) ]; then \
	#   $(MKDIR) $(openssl_BUILDDIR) && \
	#     $(CP) $(openssl_DIR)/* $(openssl_BUILDDIR)/; \
	# fi
	[ -d $(openssl_BUILDDIR) ] || $(MKDIR) $(openssl_BUILDDIR)
	cd $(openssl_BUILDDIR) && \
	  $(openssl_DIR)/Configure linux-generic64 --cross-compile-prefix=$(CROSS_COMPILE) \
	    --prefix=/ --openssldir=/lib/ssl no-tests \
		-L$(BUILDDIR)/sysroot/lib -I$(BUILDDIR)/sysroot/include

openssl_install: DESTDIR=$(BUILDDIR)/sysroot
openssl_install: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) install_sw install_ssldirs

openssl: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE)

openssl_%: $(openssl_BUILDDIR)/configdata.pm
	$(openssl_MAKE) $(@:openssl_%=%)

#------------------------------------
#
libnl_DIR=$(PROJDIR)/package/libnl
libnl_BUILDDIR=$(BUILDDIR)/libnl
libnl_MAKE=$(MAKE) DESTDIR=$(DESTDIR) -C $(libnl_BUILDDIR)

libnl_defconfig $(libnl_BUILDDIR)/Makefile:
	[ -d "$(libnl_BUILDDIR)" ] || $(MKDIR) $(libnl_BUILDDIR)
	cd $(libnl_BUILDDIR) && \
	  $(libnl_DIR)/configure --host=`$(CC) -dumpmachine` --prefix=

libnl_install: DESTDIR=$(BUILDDIR)/sysroot

libnl: $(libnl_BUILDDIR)/Makefile
	$(libnl_MAKE)

libnl_%: $(libnl_BUILDDIR)/Makefile
	$(libnl_MAKE) $(@:libnl_%=%)

#------------------------------------
# dep: openssl, libnl, linux_headers
#
wpasup_DIR=$(PROJDIR)/package/wpa_supplicant
wpasup_BUILDDIR=$(BUILDDIR)/wpasup
wpasup_MAKE=$(MAKE) CC=$(CC) LIBNL_INC="$(BUILDDIR)/sysroot/include/libnl3" \
  EXTRA_CFLAGS="-I$(BUILDDIR)/sysroot/include" LDFLAGS="-L$(BUILDDIR)/sysroot/lib" \
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

wpasup_install: DESTDIR=$(BUILDDIR)/sysroot

wpasup: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE)

wpasup_%: $(wpasup_BUILDDIR)/wpa_supplicant/.config
	$(wpasup_MAKE) $(@:wpasup_%=%)

#------------------------------------
#
mdns_DIR=$(PROJDIR)/package/mDNSResponder
mdns_BUILDDIR=$(BUILDDIR)/mdns
mdns_MAKE=$(MAKE) CC=$(CC) LD=$(LD) ST=$(STRIP) CFLAGS_PTHREAD=-pthread \
  LINKOPTS_PTHREAD=-pthread -C $(mdns_BUILDDIR)/mDNSPosix

mdns_defconfig $(mdns_BUILDDIR)/Makefile:
	[ -d $(mdns_BUILDDIR) ] || $(MKDIR) $(mdns_BUILDDIR)
	$(CP) $(mdns_DIR)/* $(mdns_BUILDDIR)/

mdns: | $(mdns_BUILDDIR)/Makefile
	$(mdns_MAKE)

mdns_%: | $(mdns_BUILDDIR)/Makefile
	$(mdns_MAKE) $(@:mdns_%=%)

#------------------------------------
# dep: ub ub_tools linux_dtbs bb dtc
# dep for bpi: linux_Image.gz
# dep for other platform: linux_bzImage
#
dist_DIR?=$(DESTDIR)
wlregdb_DIR?=$(PROJDIR)/package/wireless-regdb
ap6212_FWDIR=$(PROJDIR)/package/ap6212/linux-firmware

# reference from linux_dtbs
dist_DTINCDIR+=$(linux_DIR)/scripts/dtc/include-prefixes

dist dist_sd:
	$(MAKE) $(APP_PLATFORM)_$@

dist_%:
	$(MAKE) $(APP_PLATFORM)_$@

bpi_dist: dist_DTINCDIR+=$(linux_DIR)/arch/arm64/boot/dts/allwinner
bpi_dist: dist_dts=$(PROJDIR)/sun50i-a64-bananapi-m64.dts
bpi_dist: dist_dtb=$(linux_BUILDDIR)/arch/arm64/boot/dts/allwinner/sun50i-a64-bananapi-m64.dtb
bpi_dist: dist_loadaddr=0x40080000 # 0x40200000
bpi_dist: dist_compaddr=0x44000000
bpi_dist: dist_compsize=0xb000000
bpi_dist: dist_fdtaddr=0x4fa00000
bpi_dist: dist_log={ $(if $(2),echo $(2) >> $(BUILDDIR)/$(1), \
  echo "" > $(BUILDDIR)/$(1)); }
bpi_dist: dist_cptar_log=$(call dist_log,cptar_log.txt,$(1))
bpi_dist: dist_strip_log=$(call dist_log,strip_log.txt,$(1))
bpi_dist:
	[ -x $(PROJDIR)/tool/bin/dtc ] || $(MAKE) dtc_install
	[ -x $(PROJDIR)/tool/bin/mkimage ] || $(MAKE) ub_tools_install
ifeq ("$(NB)","")
	$(MAKE) atf_bl31 crust_scp
	$(MAKE) ub linux_Image.gz linux_dtbs linux_modules linux_headers_install \
	  zlib_install
	$(MAKE) libasound_install ncursesw_install linux_modules_install \
	  openssl_install libnl_install
	$(MAKE) alsautil_install ff_install bb_install wpasup_install
endif
	for i in dev proc root sys tmp var/run; do \
	  [ -d $(dist_DIR)/boot/$$i ] || $(MKDIR) $(dist_DIR)/boot/$$i; \
	done
	$(CP) $(ub_BUILDDIR)/u-boot-sunxi-with-spl.bin \
	  $(linux_BUILDDIR)/arch/arm64/boot/Image.gz $(dist_dtb) \
	  $(dist_DIR)/boot/
	if [ -f "$(dist_dts)" ]; then \
	  $(call CPPDTS) $(addprefix -I,$(dist_DTINCDIR)) \
	    -o $(BUILDDIR)/$(notdir $(dist_dts)) $(dist_dts) && \
	  $(call DTC2) $(addprefix -i,$(dist_DTINCDIR)) \
	    -o $(dist_DIR)/boot/$(basename $(notdir $(dist_dts))).dtb \
	    $(BUILDDIR)/$(notdir $(dist_dts)); \
	fi
	echo -n "" > $(BUILDDIR)/uboot.env.txt
	echo "loadaddr=${dist_loadaddr}" >> $(BUILDDIR)/uboot.env.txt
	echo "kernel_comp_addr_r=${dist_compaddr}" >> $(BUILDDIR)/uboot.env.txt
	echo "kernel_comp_size=${dist_compsize}" >> $(BUILDDIR)/uboot.env.txt
	echo "fdtaddr=${dist_fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	echo "loadkernel=fatload mmc 0:1 \$${loadaddr} Image.gz" >> $(BUILDDIR)/uboot.env.txt
	if [ -f "$(dist_dts)" ]; then \
	  echo "loadfdt=fatload mmc 0:1 \$${fdtaddr} $(basename $(notdir $(dist_dts))).dtb" >> $(BUILDDIR)/uboot.env.txt; \
	else \
	  echo "loadfdt=fatload mmc 0:1 \$${fdtaddr} $(basename $(notdir $(dist_dtb))).dtb" >> $(BUILDDIR)/uboot.env.txt; \
	fi
	echo "bootargs=console=ttyS0,115200n8 rootfstype=ext4,ext2 root=/dev/mmcblk2p2 rw rootwait" >> $(BUILDDIR)/uboot.env.txt
	echo "bootcmd=run loadkernel; run loadfdt; booti \$${loadaddr} - \$${fdtaddr}" >> $(BUILDDIR)/uboot.env.txt
	mkenvimage -s 131072 -o $(dist_DIR)/boot/uboot.env $(BUILDDIR)/uboot.env.txt
	$(call CP_TAR,$(dist_DIR)/rootfs,$(TOOLCHAIN_SYSROOT), \
	  --exclude="*/gconv" --exclude="*.a" --exclude="*.o" --exclude="*.la", \
	  lib lib64 sbin usr/lib usr/lib64 usr/bin usr/sbin )
	$(call CP_TAR,$(dist_DIR)/rootfs,$(BUILDDIR)/sysroot, \
	  --exclude="bin/amidi" --exclude="share/aclocal" --exclude="share/man" \
	  --exclude="share/sounds" --exclude="share/doc" \
	  --exclude="share/ffmpeg/examples" --exclude="share/ffmpeg/*.ffpreset" \
	  --exclude="share/locale", \
	  etc bin sbin share usr/bin usr/sbin var linuxrc)
	$(call CP_TAR,$(dist_DIR)/rootfs,$(BUILDDIR)/sysroot, \
	  --exclude="*.a" --exclude="*.la" --exclude="*.o", \
	  lib lib64 usr/lib usr/lib64)
	[ -d $(dist_DIR)/rootfs/lib/firmware ] || \
	  $(MKDIR) $(dist_DIR)/rootfs/lib/firmware
	$(CP) $(wlregdb_DIR)/regulatory.db $(wlregdb_DIR)/regulatory.db.p7s \
	  $(dist_DIR)/rootfs/lib/firmware/
	$(CP) $(ap6212_FWDIR)/* $(dist_DIR)/rootfs/
	$(dist_strip_log)
	for i in $(addprefix $(dist_DIR)/rootfs/, \
	    usr/lib/libgcc_s.so.1 usr/lib64/libgcc_s.so.1 \
	    bin sbin lib lib64 usr/bin usr/sbin usr/lib usr/lib64); do \
	  [ ! -e "$$i" ] && { \
	    $(call dist_strip_log,"Strip skipping missing explicite $$i"); \
	    continue; \
	  }; \
	  [ -f "$$i" ] && { \
	    $(call dist_strip_log,"Strip explicite $$i"); \
	    $(STRIP) -g $$i; \
	    continue; \
	  }; \
	  [ -d "$$i" ] && { \
	    $(call dist_strip_log,"Strip recurse dir $$i"); \
	    for j in `find $$i`; do \
	      [[ "$$j" =~ .+(\.sh|\.pl|\.py|c_rehash|ncursesw6-config|alsaconf) ]] && { \
	        $(call dist_strip_log,"Skip known script/file $$j"); \
	        continue; \
		  }; \
	      [[ "$$j" =~ .*/lib/modules/.+\.ko ]] && { \
	        $(call dist_strip_log,"Strip implicite kernel module $$j"); \
	        $(STRIP) -g $$j; \
	        continue; \
		  }; \
		  [ ! -x "$$j" ] && { \
	        $(call dist_strip_log,"Strip skipping non-executable $$j"); \
		    continue; \
		  }; \
		  [ -L "$$j" ] && { \
		    $(call dist_strip_log,"Strip skipping symbolic $$j -> `readlink $$j`"); \
		    continue; \
		  }; \
		  [ -d "$$j" ] && { \
		    $(call dist_strip_log,"Strip skipping dirname $$j"); \
		    continue; \
		  }; \
	      $(call dist_strip_log,"Strip implicite file $$j"); \
	      $(STRIP) -g $$j; \
	    done; \
	  }; \
	done
	$(CP) $(wildcard $(PROJDIR)/prebuilt/common/* \
	  $(PROJDIR)/prebuilt/$(APP_PLATFORM)/common/*) \
	  $(dist_DIR)/rootfs/
	# depmod -b $(dist_DIR)/rootfs \
	#   $(if $(wildcard $(linux_BUILDDIR)/System.map),-e -F$(linux_BUILDDIR)/System.map) \
	#   -C $(dist_DIR)/rootfs/etc/depmod.d/ $(linux_RELSTR)
	$(bb_DIR)/examples/depmod.pl \
	  -b $(dist_DIR)/rootfs/lib/modules/$(linux_RELSTR) \
	  -F $(linux_BUILDDIR)/System.map
	# du -ac $(dist_DIR) | sort -n

# sudo dd if=$(dist_DIR)/boot/u-boot-sunxi-with-spl.bin of=/dev/sdxxx bs=1024 seek=8
bpi_dist_sd:
	$(CP) $(dist_DIR)/boot/* /media/$(USER)/BOOT/
	$(CP) $(dist_DIR)/rootfs/* /media/$(USER)/rootfs/

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

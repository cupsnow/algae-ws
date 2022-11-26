#------------------------------------
#
$(eval $(call AC_BUILD2,fdkaac $(PKGDIR2)/fdk-aac $(BUILDDIR2)/fdkaac-$(APP_BUILD)))

#------------------------------------
#
$(eval $(call AC_BUILD2,faad2 $(PKGDIR2)/faad2 $(BUILDDIR2)/faad2-$(APP_BUILD)))


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
pyvenv2 pyenv2 $(BUILDDIR)/pyenv2:
	virtualenv -p python2 $(BUILDDIR)/pyenv2
	. $(BUILDDIR)/pyenv2/bin/activate && \
	  python --version && \
	  pip install sphinx_rtd_theme six

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


#------------------------------------
#
BUILDDIR?=$(abspath .)/build
DESTDIR?=$(abspath .)/destdir
MKDIR=mkdir -p
CP=cp -a

#------------------------------------
#
all: $(BUILDDIR)/eddtest1


install: all | $(DESTDIR)/bin
	$(CP) -v $(BUILDDIR)/eddtest1 $(DESTDIR)/bin

#------------------------------------
#
eddtest1_OBJS+=$(patsubst %,$(BUILDDIR)/%.o,$(wildcard *.c))
CPPFLAGS+=-Iinclude

$(BUILDDIR)/eddtest1: $(eddtest1_OBJS) | $(BUILDDIR)
	$(CC) -o $@ $(LDFLAGS) $(CFLAGS) $(eddtest1_OBJS)

$(BUILDDIR)/%.c.o: %.c | $(BUILDDIR)
	$(CC) -c -o $@ -MMD -MP -MT $@ -MF $(@).d $< $(CPPFLAGS) $(CFLAGS)

include $(wildcard $(addsuffix .d,$(eddtest1_OBJS)))


#------------------------------------
#
$(BUILDDIR) $(DESTDIR)/bin:
	$(MKDIR) $@

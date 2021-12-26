# 

bin_PROGRAMS = fftest1 evmtest1

AM_CPPFLAGS = -I$(top_srcdir)/include
AM_LDFLAGS =
LDADD = $(top_srcdir)/mod.ld

if DEBUG
AM_CPPFLAGS += -g
else
AM_CPPFLAGS += -O -ffunction-sections -fdata-sections
AM_LDFLAGS += -Wl,--gc-sections
endif

fftest1_SOURCES = fftest1.c

evmtest1_SOURCES = evmtest1.c ev.c time.c \
    mod_cli.c


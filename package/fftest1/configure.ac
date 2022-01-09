#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ([2.69])
AC_INIT([fftest1], [0.1.1], [joe@levender.local])
AM_INIT_AUTOMAKE([-Wall -Werror foreign])
AC_CONFIG_SRCDIR([fftest1.c])
AC_CONFIG_HEADERS([config.h])

# Checks for programs.
AC_PROG_CC

AC_ARG_ENABLE(debug, 
  [AS_HELP_STRING([--enable-debug], [enable debugging, default: no])],
  [],
  [enable_debug=no])

AC_MSG_CHECKING([build with debug])
AC_MSG_RESULT([$enable_debug])

AS_IF([test "x$enable_debug" != "xno"], [
  AC_DEFINE([WITH_DEBUG], [1], [build with debug])
], [])
AM_CONDITIONAL([WITH_DEBUG], [test "x$enable_debug" != "xno"])

# Checks for libraries.

AC_SEARCH_LIBS(deflate, [z], [])

# Checks for header files.
AC_CHECK_HEADERS([stdlib.h string.h unistd.h])

AC_CHECK_HEADERS([cJSON.h])

# Check ffmpeg
AC_CHECK_HEADERS([libavutil/avutil.h \
  libavcodec/avcodec.h \
  libavformat/avformat.h \
  libswresample/swresample.h], [], [enable_ffmpeg=no])

# libswresample dep: libavutil
# libavcodec dep: libswresample libavutil libz
# libavformat dep: libavcodec libavutil
AC_SEARCH_LIBS(av_frame_alloc, [avutil], [], [enable_ffmpeg=no])
AC_SEARCH_LIBS(swr_init, [swresample], [], [enable_ffmpeg=no])
AC_SEARCH_LIBS(avcodec_free_context, [avcodec], [], [enable_ffmpeg=no])
AC_SEARCH_LIBS(avformat_query_codec, [avformat], [], [enable_ffmpeg=no])

AC_MSG_CHECKING([build with ffmpeg])
AC_MSG_RESULT([$enable_ffmpeg])

AS_IF([test "x$enable_ffmpeg" != "xno"], [
  AC_DEFINE([WITH_FFMPEG], [1], [build with ffmpeg])
], [])
AM_CONDITIONAL([WITH_FFMPEG], [test "x$enable_ffmpeg" != "xno"])

# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_SIZE_T

# Checks for library functions.
AC_CHECK_FUNCS([memmove])

AC_CONFIG_FILES([
	Makefile
])

AC_OUTPUT

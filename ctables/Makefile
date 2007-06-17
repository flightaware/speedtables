#
# Makefile for installing the ctable package.
#
# Set INSTDIR to where you want it to be installed.  The parent directory
# needs to be in your Tcl auto_path list or it won't be findable when you
# do a "package require ctable"
#
# $Id$
#

INSTDIR=/usr/local/lib/ctable

test:
	cd tests; make

install:
	-mkdir -p $(INSTDIR)
	-cp -f *.tcl *-subst *.h *.c skiplists/*.h skiplists/*.c hash/speedtables.h hash/speedtableHash.c $(INSTDIR)


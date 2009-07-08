#
# Makefile for installing the ctable package.
#
# Set INSTDIR to where you want it to be installed.  The parent directory
# needs to be in your Tcl auto_path list or it won't be findable when you
# do a "package require ctable"
#
# $Id$
#

PREFIX=/usr/local
INSTDIR=$(PREFIX)/lib/ctable_server
BINDIR=$(PREFIX)/bin
TCLSH=tclsh8.5

pkgIndex.tcl:	ctable_client.tcl ctable_server.tcl
	echo "pkg_mkIndex . *.tcl" | $(TCLSH)

all:	pkgIndex.tcl

install:	all
	-mkdir -p $(INSTDIR)
	-cp -f *.tcl $(INSTDIR)
	-install -m 755 sttp $(BINDIR)

test:
	cd tests; make


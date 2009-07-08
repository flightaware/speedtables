#
# Makefile for speedtables STAPI - speedtables API
#
# $Id$
#

PREFIX=/usr/local
INSTDIR=$(PREFIX)/lib/stapi
TCLSH=tclsh8.5

V=""
V=-verbose

DIRS=client server display

CLIENT=client/client.tcl client/pgsql.tcl client/extend.tcl client/shared.tcl
SERVER=server/server.tcl server/lock.tcl
DISPLAY=display/display.tcl display/test.tcl
COMMON=debug.tcl pgsql.tcl stapi.tcl copy.tcl
TEST=server/test.tcl client/test.tcl

SRC=$(CLIENT) $(SERVER) $(DISPLAY) $(COMMON)

all: pkgIndex.tcl

pkgIndex.tcl: Makefile $(SRC)
	echo "pkg_mkIndex $V . $(SRC)" | $(TCLSH)

clean:
	rm -r ctables

test: pkgIndex.tcl $(TEST)
	server/test.tcl
	client/test.tcl

install:
	for d in . $(DIRS); do mkdir -p $(INSTDIR)/$$d; cp -f $$d/*.tcl $(INSTDIR)/$$d; done



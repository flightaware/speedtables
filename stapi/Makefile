
V=""
V=-verbose

CLIENT=client/client.tcl client/pgsql.tcl client/optimizer.tcl client/extend.tcl client/shared.tcl
SERVER=server/server.tcl server/lock.tcl
DISPLAY=display/display.tcl display/test.tcl
COMMON=debug.tcl pgsql.tcl stapi.tcl copy.tcl
TEST=server/test.tcl client/test.tcl

SRC=$(CLIENT) $(SERVER) $(DISPLAY) $(COMMON)

all: pkgIndex.tcl

pkgIndex.tcl: Makefile $(SRC)
	echo "pkg_mkIndex $V . $(SRC)" | tclsh8.4

clean:
	rm -r ctables

test: pkgIndex.tcl $(TEST)
	server/test.tcl
	client/test.tcl


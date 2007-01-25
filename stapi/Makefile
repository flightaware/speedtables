
V=""
V=-verbose

CLIENT=client/client.tcl client/pgtcl.tcl client/optimizer.tcl
SERVER=server/server.tcl server/lock.tcl
DISPLAY=display/display.tcl display/util.tcl
COMMON=debug.tcl pgsql.tcl sttp.tcl
CA=sc-ca/client_glue.tcl sc-ca/server_glue.tcl
TEST=server/test.tcl client/test.tcl

SRC=$(CLIENT) $(SERVER) $(DISPLAY) $(COMMON) $(CA)

all: pkgIndex.tcl

pkgIndex.tcl: Makefile $(SRC)
	echo "pkg_mkIndex $V . $(SRC)" | tclsh8.4

clean:
	rm -r ctables

test: pkgIndex.tcl $(TEST)
	server/test.tcl
	client/test.tcl


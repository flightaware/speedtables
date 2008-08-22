#
# run some tests
#
# $Id$
#

# default 
TCLSH=tclsh8.4
TCLSHM=$(TCLSH)

# With full memory debugging
#TCLSH=tclsh8.4m
#TCLSHM=$(TCLSH)

# With shared memory debugging
#TCLSH=tclsh8.4
#TCLSHM=$(TCLSH)m

all:
	-rm -r build
	$(TCLSH) serious-tests.tcl
	$(TCLSH) incr-test.tcl
	$(TCLSH) all-field-types.tcl
	$(TCLSH) reset-test.tcl
	$(TCLSH) tsv-nokey-tests.tcl
	$(TCLSH) tsv-tests.tcl
	$(TCLSH) new-tests.tcl
	$(TCLSH) key-tests.tcl
	$(TCLSH) trans-tests.tcl
	$(TCLSH) poll-tests.tcl
	$(TCLSH) multitable-tests.tcl
	$(TCLSH) null-tests.tcl
	rm -r build
	$(TCLSH) index-compare.tcl

compare:
	-rm -r build
	$(TCLSH) index-compare.tcl

null:
	-rm -r build
	$(TCLSH) null-tests.tcl

indef:
	-rm -r build
	$(TCLSH) index-defaults.tcl

key:
	-rm -r build
	$(TCLSH) new-tests.tcl
	mkdir tmpdir
	mv build/*.so tmpdir
	$(TCLSH) key-tests.tcl
	rm build/*.so build/topbrandsgenkey*
	mv tmpdir/* build
	rmdir tmpdir
	$(TCLSH) key-tests.tcl

master:
	-rm -r build
	-rm -f *.dat
	$(TCLSH) tsv-nokey-tests.tcl
	$(TCLSHM) master.tcl
	$(TCLSHM) master2.tcl
	rm -f *.dat

speed:
	-rm -r build
	-rm -f *.dat
	$(TCLSH) masterspeed.tcl

pools:
	-rm -r build
	-rm -f *.dat
	$(TCLSH) poolspeed.tcl

reader:
	-rm -r build
	-rm -f *.dat
	sh master+reader.sh
	rm -f *.dat

stapi:
	-rm -r build
	-rm -f *.dat
	sh stapi.sh
	rm -f *.dat

multireader:
	-rm -r build
	-rm -f *.dat
	sh multireader.sh
	rm -f *.dat

speedreader:
	-rm -r build
	-rm -f *.dat
	sh multireader.sh 1 10000000 1 10
	rm -f *.dat

readerperf:
	-rm -r build
	-rm -f *.dat
	sh readerperf.sh
	rm -f *.dat


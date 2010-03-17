#
# run some tests
#
# $Id$
#

# default 
TCLSH=tclsh`cat version`
TCLSHM=$(TCLSH)

# With full memory debugging
#TCLSH=tclsh8.4m
#TCLSHM=$(TCLSH)

# With shared memory debugging
#TCLSH=tclsh8.4
#TCLSHM=$(TCLSH)m

all:
	-rm -r stobj
	$(TCLSH) speedtable.tcl
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
	rm -r stobj
	$(TCLSH) index-compare.tcl
	-rm -r stobj
	$(TCLSH) index-defaults.tcl
	$(TCLSH) filter.tcl

compare:
	-rm -r stobj
	$(TCLSH) index-compare.tcl

null:
	-rm -r stobj
	$(TCLSH) null-tests.tcl

indef:
	-rm -r stobj
	$(TCLSH) index-defaults.tcl

master:
	-rm -r stobj
	-rm -f *.dat
	$(TCLSH) tsv-nokey-tests.tcl
	$(TCLSHM) master.tcl
	$(TCLSHM) master2.tcl
	rm -f *.dat

speed:
	-rm -r stobj
	-rm -f *.dat
	$(TCLSH) masterspeed.tcl

pools:
	-rm -r stobj
	-rm -f *.dat
	$(TCLSH) poolspeed.tcl

reader:
	-rm -r stobj
	-rm -f *.dat
	sh master+reader.sh
	rm -f *.dat

stapi:
	-rm -r stobj
	-rm -f *.dat
	sh stapi.sh
	rm -f *.dat

stapi2:
	-rm -r stobj
	-rm -f *.dat
	sh stapi.sh -d 100 -c 40 -s stapi2.tcl
	rm -f *.dat

stapi3:
	-rm -r stobj
	-rm -f *.dat
	sh stapi.sh -d 1 -c 40 -s stapi3.tcl
	rm -f *.dat

filter:
	-rm -r stobj
	$(TCLSH) filter.tcl

multireader:
	-rm -r stobj
	-rm -f *.dat
	sh multireader.sh
	rm -f *.dat

speedreader:
	-rm -r stobj
	-rm -f *.dat
	sh multireader.sh 1 1000000 5 10
	rm -f *.dat

readerperf:
	-rm -r stobj
	-rm -f *.dat
	sh readerperf.sh
	rm -f *.dat


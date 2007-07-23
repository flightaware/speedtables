#
# run some tests
#
# $Id$
#

all:
	-rm build/*
	tclsh8.4 serious-tests.tcl
	tclsh8.4 incr-test.tcl
	tclsh8.4 all-field-types.tcl
	tclsh8.4 reset-test.tcl
	tclsh8.4 tsv-nokey-tests.tcl
	tclsh8.4 tsv-tests.tcl
	tclsh8.4 new-tests.tcl
	tclsh8.4 key-tests.tcl
	tclsh8.4 trans-tests.tcl

key:
	-rm -f build/*
	tclsh8.4 key-tests.tcl

master:
	-rm -f build/* *.dat
	tclsh8.4 tsv-nokey-tests.tcl
	tclsh8.4 master.tcl
	rm -f *.dat


#
# run some tests
#
# $Id$
#

all: test-data.txt
	-rm build/*
	tclsh8.4 index-test.tcl
	tclsh8.4 match-test-index.tcl
	tclsh8.4 match-test-index2.tcl
	tclsh8.4 match-test-index3.tcl
	tclsh8.4 match-test-index4.tcl
	tclsh8.4 match-test.tcl
	tclsh8.4 name-data-index.tcl
	tclsh8.4 name-data-then-index.tcl
	tclsh8.4 range-test.tcl
	tclsh8.4 reset-test.tcl

test-data.txt: namegenerator/gen1000knames.tcl
	cd namegenerator ; tclsh8.4 gen1000knames.tcl > ../test-data.txt


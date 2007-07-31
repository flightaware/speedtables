#
# run some tests
#
# $Id$
#

all:
	-rm -r build
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
	-rm -r build
	tclsh8.4 new-tests.tcl
	mkdir tmpdir
	mv build/*.so tmpdir
	tclsh8.4 key-tests.tcl
	rm build/*.so build/topbrandsgenkey*
	mv tmpdir/* build
	rmdir tmpdir
	tclsh8.4 key-tests.tcl

master:
	-rm -r build
	-rm -f *.dat
	tclsh8.4 tsv-nokey-tests.tcl
	tclsh8.4 master.tcl
	tclsh8.4 master2.tcl
	rm -f *.dat

reader:
	-rm -r build
	-rm -f *.dat
	sh master+reader.sh
	rm -f *.dat

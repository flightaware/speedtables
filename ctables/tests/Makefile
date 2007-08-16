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
	tclsh8.4m master.tcl
	tclsh8.4m master2.tcl
	rm -f *.dat

speed:
	-rm -r build
	-rm -f *.dat
	tclsh8.4 masterspeed.tcl

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


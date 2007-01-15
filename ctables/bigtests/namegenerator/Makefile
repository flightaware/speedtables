#
# ctables - makefile for bigtests name generator
#
# $Id$
#

../test-data.txt:	FirstNames.txt LastNames.txt gen1000knames.tcl Makefile
	tclsh8.4 gen1000knames.tcl >../test-data.txt

../test-data-macs-and-ips.txt:	../test-data.txt gen1000kethers.tcl Makefile
	tclsh8.4 gen1000kethers.tcl >../test-data-macs-and-ips.txt

all:	../test-data.txt ../test-data-macs-and-ips.txt

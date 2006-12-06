#
# ctables - makefile for bigtests name generator
#
# $Id$
#

../test-data.txt:	FirstNames.txt LastNames.txt gen1000knames.tcl Makefile
	tclsh8.4 gen1000knames.tcl >../test-data.txt

all:	../test-data.txt

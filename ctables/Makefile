#
# Makefile for installing the ctable package.
#
# Set INSTDIR to where you want it to be installed.  The parent directory
# needs to be in your Tcl auto_path list or it won't be findable when you
# do a "package require ctable"
#
# $Id$
#

INSTDIR=/usr/local/lib/ctable
WORKDIR=`pwd`
TCLLIBPATH="${WORKDIR} ${WORKDIR}/../ctable_server ${WORKDIR}/../stapi"

default: test

alltest: bigtest test

bigtest: sysconfig.tcl
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd bigtests; make"

test: sysconfig.tcl
	@echo TCLLIBPATH=${TCLLIBPATH}
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make"

flairtest: sysconfig.tcl
	@echo TCLLIBPATH=${TCLLIBPATH}
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd playpen/flair; tclsh crash2.tcl"

mttest: sysconfig.tcl
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make multitable"

keytest: sysconfig.tcl
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make key"

mastertest: sysconfig.tcl
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make master"

readertest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make reader"

multitest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make multireader"

speedtest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make speedreader"

perftest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make speed"

pooltest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make pools"

stapitest: sysconfig.tcl
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make stapi"

debug:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; gdb /usr/local/bin/tclsh8.4 -c tclsh8.4.*core"

mdebug:
	sh -c "export TCLLIBPATH=${TCLLIBPATH}; cd tests; gdb /usr/local/bin/tclsh8.4m -c tclsh8.4m.core"

install: sysconfig.tcl
	-mkdir -p $(INSTDIR)
	-cp -f *.tcl *-subst *.h *.c skiplists/*.h skiplists/*.c hash/speedtables.h hash/speedtableHash.c shared/*.[ch] $(INSTDIR)

sysconfig.tcl: mkConfig.sh config.tcl
	./mkConfig.sh > sysconfig.tcl

compare:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make compare"

null:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make null"

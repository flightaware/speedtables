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

default: test

alltest: bigtest test

bigtest:
	env TCLLIBPATH=${WORKDIR} sh -c "cd bigtests; make"

test:
	env TCLLIBPATH=${WORKDIR} sh -c "cd tests; make"

keytest:
	env TCLLIBPATH=${WORKDIR} sh -c "cd tests; make key"

mastertest:
	env TCLLIBPATH=${WORKDIR} sh -c "cd tests; make master"

readertest:
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${WORKDIR} sh -c "cd tests; make reader"

debug:
	env TCLLIBPATH=${WORKDIR} sh -c "cd tests; gdb /usr/local/bin/tclsh8.4 -c tclsh8.4.core"

mdebug:
	sh -c "export TCLLIBPATH=${WORKDIR}; cd tests; gdb /usr/local/bin/tclsh8.4m -c tclsh8.4m.core"

install:
	-mkdir -p $(INSTDIR)
	-cp -f *.tcl *-subst *.h *.c skiplists/*.h skiplists/*.c hash/speedtables.h hash/speedtableHash.c shared/*.[ch] $(INSTDIR)


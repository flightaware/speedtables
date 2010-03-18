#
# Makefile for installing the ctable package.
#
# Set INSTDIR to where you want it to be installed.  The parent directory
# needs to be in your Tcl auto_path list or it won't be findable when you
# do a "package require ctable"
#
# $Id$
#

PREFIX=/usr/local
INSTDIR=$(PREFIX)/lib/ctable
WORKDIR=`pwd`
TCLLIBPATH="${WORKDIR} ${WORKDIR}/../ctable_server ${WORKDIR}/../stapi"
#
# TODO - make this automatic
#
TCLVER=8.5
TCLSH=tclsh$(TCLVER)

default: test

alltest: bigtest test

bigtest: config
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd bigtests; make"

test: config
	@echo TCLLIBPATH=${TCLLIBPATH}
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make"

flairtest: config
	rm -r playpen/flair/build
	@echo TCLLIBPATH=${TCLLIBPATH}
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd playpen/flair; $(TCLSH) crash2.tcl"

mastertest: config server
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make master"

readertest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make reader"

multitest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make multireader"

speedtest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make speedreader"

perftest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make speed"

pooltest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make pools"

stapitest: config server
	rm -f tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make stapi"

stapitest2: config server
	rm -rf tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make stapi2"

stapitest3: config server
	rm -rf tests/sharedebug.out
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make stapi3"

filtertest: config server
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make filter"

filtertest2: config server
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make filter2"

debug:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; gdb $(PREFIX)/bin/$(TCLSH) -c $(TCLSH).*core"

mdebug:
	sh -c "export TCLLIBPATH=${TCLLIBPATH}; cd tests; gdb $(PREFIX)/bin/$(TCLSH)m -c $(TCLSH)m.core"

install: config
	-mkdir -p $(INSTDIR)
	-cp -f *.tcl *-subst *.h *.c skiplists/*.h skiplists/*.c hash/speedtables.h hash/speedtableHash.c shared/*.[ch] $(INSTDIR)

sysconfig.sh: Makefile
	echo "TCLVER=$(TCLVER)" > sysconfig.sh

tests/version: Makefile
	echo "$(TCLVER)" > tests/version

sysconfig.tcl: mkConfig.sh config.tcl
	./mkConfig.sh > sysconfig.tcl

clean:
	rm sysconfig.sh sysconfig.tcl tests/version

config: sysconfig.sh sysconfig.tcl tests/version

server: ../ctable_server/pkgIndex.tcl

../ctable_server/pkgIndex.tcl: ../ctable_server/Makefile
	cd ../ctable_server && make

compare:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make compare"

null:
	env TCLLIBPATH=${TCLLIBPATH} sh -c "cd tests; make null"

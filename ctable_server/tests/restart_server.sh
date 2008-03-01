#!/bin/sh

# $Id$

TCLSH=/usr/local/bin/tclsh8.4
URL=ctable://localhost:1984/test
LOGFILE=${1:-server.log}

echo "`date` $0 $*" >> $LOGFILE

echo "`date` ../sttp $URL shutdown -nowait" >> $LOGFILE
# Don't care what the result is
../sttp "$URL" shutdown -nowait > /dev/null 2>&1

echo "`date` ${TCLSH} test_server.tcl $URL" >> $LOGFILE
# Start the server
${TCLSH} test_server.tcl "$URL" 2>> $LOGFILE &


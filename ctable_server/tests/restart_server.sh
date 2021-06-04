#!/bin/sh

# $Id$

if [ -z "$TCLSH" ]
then
  TCLVERSION=8.6

  for tclsh in /usr/bin/tclsh${TCLVERSION} /usr/local/bin/tclsh${TCLVERSION}
  do
    if [ -f $tclsh ]
    then
      TCLSH=$tclsh
      break
    fi
  done
fi

if [ -z "$TCLSH" ]
then
  echo "Can't find Tcl"
  exit 1
fi


URL=sttp://localhost:1984/test
LOGFILE=${1:-server.log}

case "$TCLSH" in
  /usr/bin*) export TCLLIBPATH="$TCLLIBPATH /usr/local/lib";;
esac

echo "`date` $0 $*" >> $LOGFILE

echo "`date` ../sttp $URL shutdown -nowait" >> $LOGFILE
# Don't care what the result is
../sttp "$URL" shutdown -nowait > /dev/null 2>&1

echo "`date` ${TCLSH} test_server.tcl $URL" >> $LOGFILE
# Start the server
${TCLSH} test_server.tcl "$URL" 2>> $LOGFILE &


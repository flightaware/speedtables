#!/bin/sh

# $Id$

TCLVERSION=8.5

for tclsh in /usr/bin/tclsh${TCLVERSION} /usr/local/bin/tclsh${TCLVERSION}
do
  if [ -f $tclsh ]
  then TCLSH=$tclsh; break
  fi
done

if [ -z "$TCLSH" ]
then
  echo "Can't find Tcl"
  exit 1
fi

URL=sttp://localhost:1984/test

case "$TCLSH" in
  /usr/bin*) export TCLLIBPATH="$TCLLIBPATH /usr/local/lib";;
esac

# Don't care what the result is
../sttp $URL shutdown -nowait > /dev/null 2>&1

# Rebuild the ctable
rm -rf build
${TCLSH} test.ct

echo "`date` $0 $*" > server.log

fail=0
success=0
for test
do
  # Start the server
  ${TCLSH} test_server.tcl 2>> server.log &
  pid=$!

  # Wait for it to start
  sleep 1
  echo "`date` sttp $URL methods" >> server.log
  if ../sttp $URL methods > /dev/null
  then : OK
  else 
    echo "# server failed"
    cat server.log
    exit -1
  fi

  echo "`date` ${TCLSH} test_$test.tcl" >> server.log
  if ${TCLSH} test_$test.tcl
  then
    echo "# $test OK"
    success=`expr $success + 1`
  else
    echo "# $test failed"
    fail=`expr $fail + 1`
  fi

  sleep 1
  # Stop the server
  echo "`date` sttp $URL shutdown -nowait" >> server.log
  ../sttp $URL shutdown -nowait > /dev/null 2>&1

  sleep 1
  if kill -0 $pid 2>/dev/null
  then
    echo "# Server not shut down properly"
    echo + kill $pid
    kill $pid
    fail=`expr $fail + 1`
    cat server.log
  fi
done

echo "# $success OK $fail failed"

exit $failed

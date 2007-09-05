#!/bin/sh

# $Id$

#TCLSH=/usr/fa/bin/tclsh8.4
TCLSH=/usr/local/bin/tclsh8.4

echo + ${TCLSH} test.ct
${TCLSH} test.ct
echo + ${TCLSH} test_server.tcl \&
${TCLSH} test_server.tcl &
pid=$!
echo + sleep 5
sleep 5

if kill -0 $pid 2>/dev/null
then
  echo "# server OK"
else
  echo "# server failed"
  exit -1
fi

fail=0
success=0
for test
do
  echo + ${TCLSH} test_$test.tcl
  if ${TCLSH} test_$test.tcl
  then
    echo "# $test OK"
    success=`expr $success + 1`
  else
    echo "# $test failed"
    fail=`expr $fail + 1`
  fi
done

sleep 5
if kill -0 $pid 2>/dev/null
then
  echo "# Server not shut down properly"
  echo + kill $pid
  kill $pid
  fail=`expr $fail + 1`
fi
echo "# $success OK $fail failed"

exit $failed

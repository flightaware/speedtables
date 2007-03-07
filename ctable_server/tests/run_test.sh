#!/bin/sh

# $Id$

echo + tclsh8.4 test.ct
tclsh8.4 test.ct
echo + tclsh8.4 test_server.tcl \&
tclsh8.4 test_server.tcl &
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
  echo + tclsh8.4 test_$test.tcl
  if tclsh8.4 test_$test.tcl
  then
    echo "# $test OK"
    success=`expr $success + 1`
  else
    echo "# $test failed"
    fail=`expr $fail + 1`
  fi
done

if kill -0 $pid 2>/dev/null
then
  echo "# Server not shut down properly"
  echo + kill $pid
  kill $pid
  fail=`expr $fail + 1`
fi
echo "# $success OK $fail failed"

exit $failed

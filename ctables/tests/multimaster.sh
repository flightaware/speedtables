#!/bin/sh
#$Id$

. test_common.sh

delay=5
script=multiclient.tcl
logfile=serverlog_multimaster.log

while
  case "$1" in
    -d) shift; delay=$1; true;;
    -s) shift; script=$1; true;;
    *) false;;
  esac
do
  shift
done
echo "Cleaning up from previous runs"
echo "+ rm -f sharefile.dat"
rm -f sharefile.dat
echo "+ rm -rf stobj"
rm -rf stobj

echo "Starting ./multimaster.tcl"
echo "+ ${TCLSHSTAPI} ./multimaster.tcl > $logfile &"

${TCLSHSTAPI} ./multimaster.tcl > $logfile &
master_pid=$!

trap "kill $master_pid 2>/dev/null" 0
sleep $delay

while
  if grep 'register ctable' $logfile > /dev/null
  then false
  else true
  fi
do
  echo "Waiting..."
  sleep $delay
done

echo "Started ./multimaster.tcl"

echo "Running ./$script"
${TCLSHSTAPI} $script
result=$?
echo "Status=$result"

echo "Shutting down multimaster"
${TCLSHSTAPI} ./shutdown_multimaster.tcl

echo "Finished"

exit $result

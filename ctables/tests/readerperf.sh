#!/bin/sh
#$Id$

. test_common.sh

echo "Starting ./master_server.tcl"
${TCLSH} ./master_server.tcl 300 &
master_pid=$!
trap 'kill $master_pid >/dev/null' 0 2
sleep 5
echo "Started ./master_server.tcl"
sleep 5


echo "Running ./readerperf.tcl"
${TCLSH} ./readerperf.tcl
echo "Finished"

sleep 5
echo "Cleaning up"

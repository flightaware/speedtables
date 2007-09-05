#!/bin/sh
#$Id$

. test_common.sh

echo "Starting ./master_server.tcl"
${TCLSH} ./master_server.tcl &
master_pid=$!
trap 'kill $master_pid >/dev/null' 0 2
sleep 5
echo "Started ./master_server.tcl"


echo "Running ./reader.tcl"
${TCLSH} ./reader.tcl
echo "Finished"

sleep 5
echo "Cleaning up"

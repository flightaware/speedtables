#!/bin/sh
#$Id$

echo "Starting ./master_server.tcl"
tclsh8.4 ./master_server.tcl &
master_pid=$!
trap 'kill $master_pid >/dev/null' 0 2
sleep 5
echo "Started ./master_server.tcl"
sleep 5


echo "Running ./readerperf.tcl"
tclsh8.4 ./readerperf.tcl
echo "Finished"

sleep 5
echo "Cleaning up"

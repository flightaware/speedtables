#!/bin/sh
#$Id$

echo "Starting ./master_server.tcl"
tclsh8.4 ./master_server.tcl $delay $changes &
master_pid=$!
trap 'kill $master_pid 2>/dev/null' 2
sleep 5
echo "Started ./master_server.tcl"

echo "Running ./stapi.tcl"
tclsh8.4 stapi.tcl

echo "Shutting down master"
tclsh8.4 ./shutdown_master.tcl

echo "Finished"


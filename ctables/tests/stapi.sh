#!/bin/sh
#$Id$

. test_common.sh

echo "Prebuilding master table"
${TCLSH} ./master_prebuild.tcl

echo "Starting ./master_server.tcl"
${TCLSH} ./master_server.tcl $delay $changes &
master_pid=$!
trap 'kill $master_pid 2>/dev/null' 2
sleep 5
echo "Started ./master_server.tcl"

echo "Running ./stapi.tcl"
${TCLSH} stapi.tcl

echo "Shutting down master"
${TCLSH} ./shutdown_master.tcl

echo "Finished"


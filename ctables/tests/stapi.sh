#!/bin/sh
#$Id$

. test_common.sh

echo "Prebuilding master table"
${TCLSH} ./master_prebuild.tcl

delay=1
changes=66
script=stapi.tcl

while
  case "$1" in
    -d) shift; delay=$1; true;;
    -c) shift; changes=$1; true;;
    -s) shift; script=$1; true;;
    *) false;;
  esac
do
  shift
done

echo "Starting ./master_server.tcl"
echo + ${TCLSH} ./master_server.tcl $delay $changes
${TCLSH} ./master_server.tcl $delay $changes &
master_pid=$!
trap 'kill $master_pid 2>/dev/null' 2
sleep 5
echo "Started ./master_server.tcl"

echo "Running ./$script"
${TCLSH} $script

echo "Shutting down master"
${TCLSH} ./shutdown_master.tcl

echo "Finished"


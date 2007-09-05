#!/bin/sh
#$Id$

. test_common.sh

readers=${1:-10}
count=${2:-100000}
delay=${3:-20}
changes=${4:-1}

echo "Starting ./master_server.tcl"
${TCLSH} ./master_server.tcl $delay $changes &
master_pid=$!
trap 'kill $master_pid 2>/dev/null' 2
sleep 5
echo "Started ./master_server.tcl"

# in subshell so wait doesn't wait on master lol
(
trap 'kill $reader_pids 2>/dev/null' 2
echo "Running $readers readers for $count fetches"
while [ $readers -gt 0 ]
do
  ${TCLSH} ./multireader.tcl $count &
  reader_pids="$reader_pids $!"
  readers=`expr $readers - 1`
done

# Wait for all the readers to start up
sleep 5

# Master will not actually shut down until the last reader is finished
${TCLSH} ./shutdown_master.tcl

wait
)
echo "Finished"


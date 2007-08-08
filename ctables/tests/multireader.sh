#!/bin/sh
#$Id$

readers=${1:-10}
count=${1:-100000}

echo "Starting ./master_server.tcl"
tclsh8.4 ./master_server.tcl &
master_pid=$!
trap 'tclsh8.4 ./shutdown_master.tcl' 2
sleep 5
echo "Started ./master_server.tcl"

# in subshell so wait doesn't wait on master lol
(
echo "Running $readers readers for $count fetches"
while [ $readers -gt 0 ]
do
  tclsh8.4 ./multireader.tcl $count &
  readers=`expr $readers - 1`
done

# Master will not actually shut down until the last reader is finished
tclsh8.4 ./shutdown_master.tcl

wait
)
echo "Finished"

sleep 5
echo "Cleaning up"

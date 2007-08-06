#!/bin/sh
#$Id$

tclsh8.4 ./master_server.tcl &
master_pid=$!
sleep 5

tclsh8.4 ./reader.tcl

sleep 5

kill $master_pid

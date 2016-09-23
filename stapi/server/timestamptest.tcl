#!/usr/local/bin/tclsh8.4

# add new directories to make sure we're testing this version of
# stapi and speedtables
if [info exists env(ST_PREFIX)] {
  lappend auto_path $env(ST_PREFIX)
}
if [info exists env(STAPI_PREFIX)] {
  lappend auto_path $env(STAPI_PREFIX)
} else {
  set d [exec pwd]
  if [file exists $d/pkgIndex.tcl] {
    lappend auto_path $d
  }
  set d [file dirname $d]
  if [file exists $d/pkgIndex.tcl] {
    lappend auto_path $d
  } 
}
puts "Using auto_path $auto_path"

source server.tcl
#package require st_server
package require st_postgres
package require ctable
set ::ctable::genCompilerDebug 1
set quick 1

if [file exists postgres.tcl] {
	source postgres.tcl
	pgconn
} elseif [file exists ../postgres.tcl] {
	source ../postgres.tcl
	pgconn
}

# clean up, if necessary, and don't care if we fail this
pg_result [pg_exec [::stapi::conn] { DROP TABLE TS_TEST; }] -clear

# Create the timestamp test table
set r [pg_exec [::stapi::conn] {
	CREATE TABLE TS_TEST (
		id		varchar primary key,
		timestamp	timestamp,
		epoch		integer,
		payload		varchar
	);
}]
set ok [string match "PGRES_*_OK" [pg_result $r -status]]
if {!$ok} {
  error [pg_result $r -error]
}
pg_result $r -clear

proc dosql {args} {
   set r [eval [concat [list pg_exec [::stapi::conn]] $args]]
   set ok [string match "PGRES_*_OK" [pg_result $r -status]]
   if {!$ok} {
     error [pg_result $r -error]
   }
   pg_result $r -clear
}
   

global id
set id 1
proc post {epoch payload} {
	global id
	set stamp [::stapi::clock2sqlgmt $epoch]
	dosql {INSERT INTO TS_TEST (id, timestamp, epoch, payload) VALUES ($1, $2, $3, $4);} $id $stamp $epoch $payload
	incr id
}
	
global fake_time
set fake_time [expr {[clock seconds] - (365 * 24 * 60 * 60)}]

proc post_n {n p} {
    global fake_time
    for {set i 0} {$i < $n} {incr i} {
	incr fake_time [expr $i + 1337]
	post $fake_time "$p $i"
    }
}

post_n 1000 squirrel

pg_select [::stapi::conn] "select count(*) from ts_test;" row { set count $row(count) }
puts "select count(*) from ts_test; -> $count"

set columns [
	::stapi::from_table ts_test id -timestamp timestamp
]

puts "timestamp columns are [list $columns]"

# Set up the ctable
::stapi::init_ctable ts_test {} "" $columns

# Open and read it
set timestamp_table [::stapi::open_cached ts_test]

# Check size
puts "timestamp: \[$timestamp_table count] = [$timestamp_table count]"

# Create another 20 elements
post_n 20 moose

set n [::stapi::refresh_ctable $timestamp_table]

puts "read $n total now [$timestamp_table count]"

# Create another 20 elements
post_n 20 boris

set n [::stapi::refresh_ctable $timestamp_table]

puts "read $n total now [$timestamp_table count]"

# Create another 20 elements
post_n 20 natasha

set n [::stapi::refresh_ctable $timestamp_table]

puts "read $n total now [$timestamp_table count]"

set columns [
	::stapi::from_table ts_test id -timestamp epoch
]

puts "epoch columns are [list $columns]"

# Set up the ctable
::stapi::init_ctable epoch_test {ts_test} "" $columns

# Open and read it
set epoch_table [::stapi::open_cached epoch_test]

# Check size
puts "epoch: \[$epoch_table count] = [$epoch_table count]"

# Create another 20 elements
post_n 20 huckleberry

set n [::stapi::refresh_ctable $epoch_table]

puts "read $n total now [$epoch_table count]"

# Create another 20 elements
post_n 20 yogi

set n [::stapi::refresh_ctable $epoch_table]

puts "read $n total now [$epoch_table count]"

# Create another 20 elements
post_n 20 scoobie

set n [::stapi::refresh_ctable $epoch_table]

puts "read $n total now [$epoch_table count]"

# Update the original table
set n [::stapi::refresh_ctable $timestamp_table]

puts "read $n total now [$timestamp_table count]"


#!/usr/local/bin/tclsh8.4

# put new directories first to make sure we're testing this version of
# stapi and speedtables
set __new_path {}
if [info exists env(ST_PREFIX)] {
  lappend __new_path $env(ST_PREFIX)
}
if [info exists env(STAPI_PREFIX)] {
  lappend __new_path $env(STAPI_PREFIX)
} else {
  lappend __new_path [exec pwd]
}
set auto_path [concat $__new_path $auto_path]

source server.tcl
package require st_postgres
package require ctable
set ::ctable::genCompilerDebug 1
set quick 1

source postgres.tcl
pgconn

# clean up, if necessary, and don't care if we fail this
pg_result [pg_exec [::stapi::conn] { DROP TABLE TS_TEST; }] -clear

# Create the timestamp test table
set r [pg_exec [::stapi::conn] {
	CREATE TABLE TS_TEST (
		id		varchar primary key,
		timestamp	timestamp,
		epoch		integer,
		payoad		varchar
	);
}]
set ok [string match "PGRES_*_OK" [pg_result $r -status]]
if {!$ok} {
  error [pg_result $r -error]
}
pg_result $r -clear

global id
set id 1
proc post {epoch payload} {
	global id
	set stamp [::stapi::clock2sqlgmt $epoch]
	pg_exec [::stapi::conn] "INSERT INTO TS_TEST (id, timestamp, epoch, payload) VALUES ($id, '$stamp', $epoch, '$payload');"
	incr id
}
	
set fake_time [expr {[clock seconds] - (365 * 24 * 60 * 60)}]
for {set i 0} {$i < 1000} {incr i} {
	incr fake_time [expr $i + 1337]
	post $fake_time "squirrel $i"
}


set columns [
	::stapi::from_table ts_test id -timestamp timestamp
]

puts "columns are [list $columns]"

# Set up the ctable
::stapi::init_ctable ts_test {} "" $columns

# Open and read it
set nr [::stapi::open_cached ts_test -col isbn -index pages]

# Check size
puts "\[$nr count] = [$nr count]"


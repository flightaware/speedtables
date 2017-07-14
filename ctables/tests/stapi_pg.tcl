package require Pgtcl

source test_common.tcl

# Explicitly pull in this version of stapi.
source ../../stapi/pgsql.tcl
source ../../stapi/server/lock.tcl
source ../../stapi/server/server.tcl

source postgres.tcl

set conn [pgconn]

::stapi::set_conn $conn

set verbose 0

proc readfile {file} {
	set fp [open $file]
	set text [read $fp]
	close $fp
	return $text
}

proc do_sql {conn sql} {
	global verbose
	if {$verbose} {puts "+ do_sql {$sql}"}
	set r [pg_exec $conn $sql]
	set s [pg_result $r -status]
	set e [pg_result $r -error]
	pg_result $r -clear
	if {"$s" != "PGRES_COMMAND_OK"} {
		puts stderr $e
		error "Postgres error $s in $sql"
	}
}

proc do_prepared {conn statement args} {
	global verbose
	if {$verbose} {puts "+ do_prepared $statement $args"}
	set r [eval [concat pg_exec_prepared [list $conn $statement] $args]]
	set s [pg_result $r -status]
	set e [pg_result $r -error]
	pg_result $r -clear
	if {"$s" != "PGRES_COMMAND_OK"} {
		puts stderr $e
		error "Postgres error $s in prepared statement $statement $args"
	}
}

puts stderr "Cleaning up DB"
set r [pg_exec $conn [readfile pgtcl_cleanup.sql]]
pg_result $r -clear

puts stderr "Set up DB"
do_sql $conn [readfile pgtcl_create.sql]

# prepared statements are case sensitive lowercase even if declared uppercase.
do_sql $conn {PREPARE INSERTANIMAL AS INSERT INTO TEST_ANIMALS (ID, TYPE, NAME, WEIGHT) VALUES ($1, $2, $3, $4);}

puts stderr "Insert big animals"
array set animals {
	1	{type cow name bessie weight 1000}
	2	{type cow name bossie weight 1000}
	3	{type dog name dog weight 35}
	4	{type dog name spot weight 37}
	5	{type cat name puss weight 10}
	6	{type rooster name boss weight 17}
	7	{type pangolin name bob weight 26}
}

puts stderr "Insert big animals"
set oweight 0
foreach id [array names animals] {
	array set row $animals($id)
	incr oweight $row(weight)
	do_prepared $conn insertanimal $id $row(type) $row(name) $row(weight)
}

puts stderr "Insert small animals"
for {set i 1} {$i < 100} {incr i} {
	incr oweight 10
	do_prepared $conn insertanimal [expr 100 + $i] chicken "chicken #$i" 10
}

puts stderr "Testing postgres ... reading schema"
set schema {{_key {} TEXT(id)} {id {character varying}} {name {character varying}} {type {character varying}} {weight integer}}
set read_schema [::stapi::from_table TEST_ANIMALS id]
if {$read_schema ne $schema} {
	puts stderr "Expected $schema"
	puts stderr "Read $read_schema"
	error "Schema mismatch"
}

::stapi::init_ctable animals TEST_ANIMALS "" [::stapi::from_table TEST_ANIMALS id]
puts stderr "Building ctable"
::stapi::init_ctable animals TEST_ANIMALS "" [::stapi::from_table TEST_ANIMALS id]
set a [::stapi::open_cached animals]

set sql "select ID, TYPE, NAME, WEIGHT from TEST_ANIMALS;"
::stapi::read_ctable_from_sql $a $sql

$a search -array row -code {
	incr nweight $row(weight)
}
puts "original weight $oweight - new weight $nweight"
if {$oweight != $nweight} {
	error "Weights didn't match!"
}
puts "Imported results matched."

set ::pongcount 0
proc pong {} {
   incr ::pongcount
   after 1 pong
}

# prime the pump
pong

# Simple dumb test using read_ctable_from_sql_rowbyrow_full explicitly
set ::pongcount 0
::stapi::read_ctable_from_sql_rowbyrow_full $a $sql 1 0

set expected [$a count]

if {$::pongcount != $expected} {
	error "pong called $::pongcount times - expected $expected"
}

puts "pong called $::pongcount times - total rows [$a count]"

# Switch to polled table, and use reload_ctable to test
$a destroy
set a [::stapi::open_cached animals -rowbyrow 1 -polling 1]

set ::pongcount 0
::stapi::reload_ctable $a

set expected [$a count]

if {$::pongcount != $expected} {
	error "pong called $::pongcount times - expected $expected"
}

$a clean

set delsql "DELETE FROM TEST_ANIMALS WHERE ID = '2';"
set r [pg_exec $conn $delsql]
set s [pg_result $r -status]
set e [pg_result $r -error]
pg_result $r -clear
if {"$s" != "PGRES_COMMAND_OK"} {
	error "Postgres error $e in $delsql"
}

set sql "select ID, TYPE, NAME, WEIGHT from TEST_ANIMALS;"
::stapi::read_ctable_from_sql_full $a $sql 0 1
set dirty_animals [list]
$a search -compare {{= _dirty 0}} -array r -code {
	lappend dirty_animals $r(name)
}

if {"$dirty_animals" != "bossie"} {
	error "Clean/dirty test expecting to only find "bossie" got "$dirty_animals"
}
set c [$a search -compare {{= _dirty 0}} -delete 1]
if {$c != 1} {
	error "Clean/dirty test expecting to delete 1 actually deleted $c"
}

puts "\nDone"

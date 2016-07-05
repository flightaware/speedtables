package require Pgtcl

source test_common.tcl

namespace eval ctable {
	set genCompilerDebug 1
}


source postgres.tcl

set conn [pgconn]

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
do_sql $conn {PREPARE INSERTANIMAL AS INSERT INTO ANIMALS (ID, TYPE, NAME, WEIGHT) VALUES ($1, $2, $3, $4);}

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

puts stderr "Insert small animals"
set oweight 0
foreach id [array names animals] {
	array set row $animals($id)
	incr oweight $row(weight)
	do_prepared $conn insertanimal $id $row(type) $row(name) $row(weight) }

for {set i 1} {$i < 100} {incr i} {
	incr oweight 10
	do_prepared $conn insertanimal [expr 100 + $i] chicken "chicken #$i" 10
}

puts stderr "Building ctable"
source pgtcl_ctable.tcl

puts stderr "Creating ctable"
set a [Animals create #auto]

puts stderr "Import test"
set r [pg_exec $conn "select id, name, type, weight from animals;"]
puts "  results"
    puts "    status    [pg_result $r -status]"
    puts "    numTuples [pg_result $r -numTuples]"
    puts "    conn      [pg_result $r -conn]"
$a import_postgres_result $r
pg_result $r -clear
puts "Import complete"

set nweight 0
$a search -array row -code {
	incr nweight $row(weight)
}
puts "original weight $oweight - new weight $nweight"
if {$oweight != $nweight} {
	error "Weights didn't match!"
}
puts "Imported results matched."

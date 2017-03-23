#
# $Id$
#

source test_common.tcl

#source multitable.ct

package require st_shared

puts "Checking one connection..."
set nameval [::stapi::connect shared://1616/nameval -build stobj]

set count 0
$nameval search -array row -code {
	incr count
	if {"$row(name)" != "name$row(_key)"} {
		error "Expected $row(name) == name$row(_key) for row $row(_key)"
	}
}
if {$count != 1000} {
	error "Expected 1000 rows got $count"
}

$nameval destroy

puts "Checking two connections and disconnecting one..."
set nameval [::stapi::connect shared://1616/nameval -build stobj]
set elements [::stapi::connect shared://1616/elements -build stobj]

$nameval destroy

set count 0
$elements search -array row -code {
        incr count
}
if {$count != 10} {
	error "Expected 10 rows got $count"
}

set count 0
$elements search -compare {{= name Beryllium}} -array row -code {
	incr count
	if {"$row(symbol)" != "Be"} {
		error "Expected symbol 'Be' got '$row(symbol)'"
	}
}

if {$count != 1} {
	error "Expected 1 row matching 'Beryllium' got $count"
}

$elements destroy

puts "Randomly connecting and disconnecting..."
array set table_names [list 0 nameval 1 elements]
catch {array unset tables}
unset -nocomplain tables
for {set i 0} {$i < 1000} {incr i} {
    set t [expr {int(rand() * 2)}]
    if [info exists tables($t)] {
        $tables($t) destroy
	unset tables($t)
    } else {
	set tables($t) [::stapi::connect shared://1616/$table_names($t) -build stobj]
    }
    for {set j 0} {$j < 2} {incr j} {
	if [info exists tables($t)] {
	    $tables($t) search -countOnly 1
	}
    }
}

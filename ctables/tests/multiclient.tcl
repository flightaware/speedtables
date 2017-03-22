#
# $Id$
#

source test_common.tcl

#source multitable.ct

package require st_shared

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


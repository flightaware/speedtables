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


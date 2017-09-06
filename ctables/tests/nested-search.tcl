#
# $Id$
#

source test_common.tcl

source searchtest-def.tcl

source dumb-data.tcl

proc boom {} {
	t search -compare {{= alive 1}} -array a -code {
		t search -compare [list [list = coolness $a(coolness)]] -array b -code {
			set target $b(_key)
		}
		t delete $target
	}
}

if {![catch boom error]} {
	error "There should have been an eath_shattering kaboom"
} else {
	puts [list Got $error]
	if {"$error" ne "Can not delete from inside search.\n"} {
		error [list expected "Can not delete from inside search.\\n" got $error]
	}
}

puts "Nested search test passed"

#
# some tests that actually check their results
#
# $Id$
#

source test_common.tcl

package require ctable

source searchtest-def.tcl

source dumb-data.tcl

if {"[t null brock]" != "dad"} {
	error "\[t null brock] is [t null brock] and should be {dad}"
}

if {"[t isnull brock dad name]" != {1 0}} {
	error "\[t isnull brock dad name]" is [t isnull brock dad name] and should be {1 0}"
}

puts "Testing null tabsep"
set fn tmp_null_test.tsv
set fp [open $fn w]
t search -write_tabsep $fp -null "\\N" -quote escape
close $fp

t reset

set fp [open $fn r]
t read_tabsep $fp -null "\\N" -quote escape
close $fp

if {"[t null brock]" != "dad"} {
	error "After tabsep - \[t null brock] is [t null brock] and should be {dad}"
}

if {"[t isnull brock dad name]" != {1 0}} {
	error "After tabsep - \[t isnull brock dad name]" is [t isnull brock dad name] and should be {1 0}"
}

t null brock coolness

if {"[t null brock]" != "dad coolness"} {
	error "\[t null brock] is [t null brock] and should be {dad coolness}"
}

if {![t isnull brock coolness]} {
	error "brock suddenly became cool!"
}

#
# $Id$
#

source test_common.tcl

source searchtest-def.tcl

source dumb-data.tcl

puts [list t cursors = [t cursors]]

puts "Creating cursor"
set c [t search -cursor #auto]
puts [list t cursors = [t cursors]]
puts [list $c count = [$c count]]

puts [list $c index = [$c index]]
puts [list $c key = [$c key]]
puts [list $c get = [$c get]]
puts [list $c next = [$c next]]
puts [list $c key = [$c key]]
puts [list $c get = [$c get]]
puts [list $c next = [$c next]]
puts [list $c key = [$c key]]
puts [list $c array_get = [$c array_get]]
puts [list $c next = [$c next]]
puts [list $c array_get_with_nulls = [$c array_get_with_nulls]]
puts [list $c set coolness 101 alive 0 = [$c set coolness 101 alive 0 ]]
puts [list $c array_get = [$c array_get]]
puts [list $c next = [$c next]]
puts [list $c get = [$c get]]
puts [list $c next = [$c next]]
puts [list $c get = [$c get]]

puts "Destroying cursor"
$c destroy

puts [list t cursors = [t cursors]]

puts "Creating second cursor"

set c [t search -compare {{= alive 1}} -cursor #auto]
set d [t search -compare {{= alive 0}} -cursor #auto]
puts [list t cursors = [t cursors]]

puts [list $c count = [$c count]]
puts [list $d count = [$d count]]

while {[$d index] >= 0} {
	puts [list $d index = [$d index]]
	puts [list $d at_end = [$d at_end]]
	puts [list $d array_get = [$d array_get]]
	$d next
}
puts [list $d at_end = [$d at_end]]

puts "Destoying $d"
$d destroy

puts [list $c index = [$c index]]
puts [list $c get = [$c get]]
puts [list $c next = [$c next]]
puts [list $c get = [$c get]]

puts "Destoying $c"
$c destroy

puts [list t cursors = [t cursors]]

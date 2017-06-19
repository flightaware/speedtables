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

puts "Destroying $c"
$c destroy

puts "Flooding the table with extras"

for {set i 0} {$i < 10000} {incr i} {
	set n extra$i
	t set $n id $n name "Extra $i" show ALL home NONE age 0 coolness 0
}

puts "Performance tests"

proc codetest {} {
	set len 0
	::t search -array_get l -code { incr len [llength $l] }
	return $len
}

proc sorttest {} {
	set len 0
	::t search -array_get l -sort coolness -code { incr len [llength $l] }
	return $len
}

proc curstest {} {
	set len 0
	set c [::t search -cursor #auto]
	while {![$c at_end]} {
		incr len [llength [$c array_get]]
		$c next
	}
	$c destroy
	return $len
}

puts [list codetest [time codetest]]

puts [list sorttest [time sorttest]]

puts [list curstest [time curstest]]

puts "Performance tests 2"

proc codetest {} {
	set len 0
	::t search -array_get l -compare {{> coolness 0}} -code { incr len [llength $l] }
	return $len
}

proc curstest {} {
	set len 0
	set c [::t search -compare {{> coolness 0}} -cursor #auto]
	while {![$c at_end]} {
		incr len [llength [$c array_get]]
		$c next
	}
	$c destroy
	return $len
}

puts [list codetest [time codetest]]

puts [list curstest [time curstest]]

puts "Performance tests 3"

proc codetest {} {
	set len 0
	::t search -key k -code { incr len [llength $k] }
	return $len
}

proc curstest {} {
	set len 0
	set c [::t search -cursor #auto]
	while {![$c at_end]} {
		incr len [llength [$c key]]
		$c next
	}
	$c destroy
	return $len
}

puts [list codetest [time codetest]]

puts [list curstest [time curstest]]


puts [list t cursors = [t cursors]]

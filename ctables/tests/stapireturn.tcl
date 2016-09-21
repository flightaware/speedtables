#
# $Id$
#

package require st_shared

puts "Making shared connection"
set r [::stapi::connect shared://1616/master -build stobj]

puts "created reader $r"

puts [$r share list]
puts [$r share info]

proc testret_search {table} {
	set result "empty"
	$table search -array row -limit 1 -code {
		set result "bad"
		return "good"
	}
	return $result
}

# Foreach not implemented for shared ctables.
proc testret_foreach {table} {
	set result "empty"
	$table foreach ignore {
		set result "bad"
		return "good"
	}
	return $result
}

foreach test {search} {
	puts "# TESTING RETURN $test"
	set result [testret_$test $r]
	puts "# RESULT IS '$result'"
	if { "$result" != "good" } {
		error "Testing shared return for $test got '$result' instead of 'good'"
	}
}

puts "deleting shared connection"

$r destroy

puts "Making network connection"
set r [::stapi::connect sttp://localhost:1616/master]

puts "created reader $r"

puts [$r share list]
puts [$r share info]

foreach test {search} {
	puts "# TESTING RETURN $test"
	set result [testret_$test $r]
	puts "# RESULT IS '$result'"
	if { "$result" != "good" } {
		error "Testing network return for $test got '$result' instead of 'good'"
	}
}

puts "deleting network connection"

$r destroy


# $Id$

package require ctable_client

remote_ctable sttp://localhost:1984/test c_test

set status 0

if [catch {
    puts "Starting"
    c_test set a id 10 name "Line 1"
    puts "a = [c_test array_get a]"
    c_test set b id 20 name "Line 1\nLine 2"
    puts "b = [c_test array_get b]"
    set line "Paradimethylaminobenzaldehyde"
    for {set i 0} {$i < 15} {incr i} {
	puts -nonewline "\r$i ([string length $line]): "; flush stdout
	c_test set double_$i name $line
	puts -nonewline "$i.    "; flush stdout
	array set fetched [c_test array_get double_$i]
	if {"$line" != "$fetched(name)"} {
	    error "Doubling failed at $i [list $line] != [list $fetched(name)]"
        }
	set line "$line\n$line"
    }
} err] {
   puts ""
   puts "Test failed - $err"
   set status 1
} else {
   puts ""
}

if {$status} {
   exit $status
}

puts "Error handling - server"
c_test reset
for {set i 0} {$i < 10} {incr i} {
   c_test set id$i id $i name "line $i"
}
set expected_error "list must have an even number of elements"
if [catch {c_test search -error} error] {
   if {"$expected_error" != "$error"} {
      puts "Expected [list $expected_error] got [list $error]"
      set status 1
   }
} else {
   puts "Expected [list $expected_error] got success"
   set status 1
}

puts "Error handling - client"
set expected_error "Testing error"
if [catch {c_test search -key k -code { error $expected_error }} error] {
   if {"$expected_error" != "$error"} {
      puts "Expected [list $expected_error] got [list $error]"
      set status 1
   }
} else {
   puts "Expected [list $expected_error] got success"
   set status 1
}

exit $status

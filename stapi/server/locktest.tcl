#!/usr/local/bin/tclsh8.6

set id [lindex $argv 0]
set pid [pid]
expr "srand($pid)"
set delay [expr {entier(floor(rand() * 5000))}]

puts "pid $pid id $id"
source lock.tcl

if [::stapi::lockfile testlock err] {
	puts "pid $pid id $id locked testlock, sleeping ${delay}ms"
	after $delay
	::stapi::unlockfile testlock
	puts "pid $pid id $id unlocked testlock"
} else {
	puts stderr $err
}

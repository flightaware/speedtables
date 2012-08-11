# $Id$

package require ctable_client
lappend auto_path build
package require C_test

remote_ctable sttp://localhost:1984/test remote
c_test create local

set status 0

remote reset
for {set i 0} {$i < 10} {incr i} {
   remote set id$i id $i name "line $i"
}

puts "testing search"
set count [remote search -into local]
if {"$count" != "10"} {
  error "Expecting \[remote search...] to return '10', got '$count'"
}

if {"[local count]" != "10"} {
  error "Expecting \[local count] to return '10', got '[local count]'"
}

local reset

puts "testing search with action"
remote search -buffer local -array a -compare {{= id 4}} -code {
    set search_result [list $a(id) $a(name)]
}
if {![info exists search_result]} {
    error "Expecting search_result, none set"
}
if {"$search_result" != "4 {line 4}"} {
    error "Expecting '4 {line 4}' got '$search_result'"
}

exit 0

#
# $Id$
#

package require ctable_client

set suffix _m
set verbose 0

source top-brands-nokey-def.tcl

remote_ctable ctable://localhost:1616/master socket_tbl

set params [socket_tbl attach [pid]]
top_brands_nokey_m create reader_tbl reader $params

puts "created reader reader_tbl"

puts "reader_tbl share info -> [reader_tbl share info]"
puts "reader_tbl share names -> [reader_tbl share names]"
puts "reader_tbl share list -> [reader_tbl share list]"

reader_tbl search -key k -array_get a -code {
    set orig($k) $a
    array set row $a
    lappend ids $row(id)
}
set names [array names orig]
set num [llength $names]

proc searchtest {table count} {
  global names
  global num
  global orig
  for {set i 0} {$i < $count} {incr i} {
    set n [expr {int(rand() * $num)}]
    set k [lindex $names $n]
    array set row $orig($k)
    set id $row(id)
    set comp {}
    lappend comp [list = id $id]
    set found 0
    $table search -compare $comp -key k -array_get a -code {
	incr found
    }
  }
}

puts "socket_tbl search [time {searchtest socket_tbl 1000}]"
puts "reader_tbl search [time {searchtest reader_tbl 1000}]"

reader_tbl destroy
socket_tbl shutdown
socket_tbl destroy

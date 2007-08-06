#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_client

set suffix _m

source top-brands-nokey-def.tcl

remote_ctable ctable://localhost:1616/master m

set params [m attach [pid]]
puts "params=[list $params]"

top_brands_nokey_m create r reader $params

puts "created reader r"

r search -key k -array_get a -code {set orig($k) $a}
set names [array names orig]
set num [llength $names]

puts "looping"

for {set i 0} {$i < 1000} {incr i} {
    set n [expr {int(rand() * $num)}]
    set k [lindex $names $n]
    array set row $orig($k)
    r search -compare [list [list = id $row(id)]] -key k -array_get a -code {
	puts [format "%4d %4d %s : %s" $i $n $k $a]
    }
    after 15
}

puts "shutting down"

r shutdown


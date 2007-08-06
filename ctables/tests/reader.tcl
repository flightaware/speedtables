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

r search -key k -array_get a -code {set orig($k) $a; set curr($k) $a}
set names [array names orig]
set num [llength $names]

puts "Scanning 1000 samples"

for {set i 0} {$i < 1000} {incr i} {
    set n [expr {int(rand() * $num)}]
    set k [lindex $names $n]
    set old $curr($k)
    array set row $old
    set id $row(id)
    set comp {}
    lappend comp [list = id $id]
    set found 0
    r search -compare $comp -key k -array_get a -code {
	if {"$a" != "$old"} {
	    lappend changed($k) $id $a
	    set curr($k) $a
        }
	incr found
    }
    if {!$found} {
       puts "Missing $comp"
    }
    after 15
}

foreach k [lsort -integer [array names changed]] {
    puts [format "%10s : %s" $k $orig($k)]
    foreach {id a} $changed($k) {
	puts [format "%-10s > %s" "" $a]
    }
}

puts "shutting down"

m shutdown


#
# $Id$
#

package require ctable_client

set suffix _m
set verbose 0

source top-brands-nokey-def.tcl

puts "starting"

remote_ctable ctable://localhost:1616/master m
puts "opened master"

set params [m attach [pid]]
puts "params=[list $params]"

top_brands_nokey_m create r reader $params

puts "created reader r"

r search -key k -array_get a -code {
    set orig($k) $a
    set curr($k) $a
    array set row $a
    lappend ids $row(id)
}
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
    if {$i % 100 == 0} {
	puts -nonewline "$found"; flush stdout
    }
    after 15
}

puts "1000 passes [llength [array names changed]] modified"

if $verbose {
  foreach k [lsort -integer [array names changed]] {
    puts [format "%10s : %s" $k $orig($k)]
    foreach {id a} $changed($k) {
	puts [format "%-10s > %s" "" $a]
    }
  }
}

puts "Faster scanning 10000 samples"

set idcount [llength $ids]
foreach id $ids {
    set idfound($id) 0
    set idwant($id) 0
}

for {set i 0} {$i < 10000} {incr i} {
    set n [expr {int(rand() * $idcount)}]
    set id [lindex $ids $n]
    set comp {}
    lappend comp [list = id $id]
    incr idwant($id)
    set found 0
    r search -compare $comp -key k -array_get a -code {
	incr idfound($id)
	incr found
    }
    if {$i % 100 == 0} {
	puts -nonewline "$found"; flush stdout
    }
    # sleep 1ms approx 1 in 10 times
    set sleep [expr {int(rand() * 10) - 8}]
    if {$sleep > 0} {
        after 1
    }
}

puts "done"

foreach id [array names idwant] {
    if {$idwant($id) != $idfound($id)} {
	puts "$id: wanted $idwant($id) found $idfound($id)"
    }
}

puts "shutting down"

m shutdown


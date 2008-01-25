#
# $Id$
#

package require ctable_client

set suffix _m
set verbose 0

source top-brands-nokey-def.tcl

remote_ctable ctable://localhost:1616/master m

set pid [pid]
if [llength $argv] {
  set count [lindex $argv 0]
} else {
  set count 100000
}

set params [m attach $pid]

top_brands_nokey_m create r reader $params

r search -array row -code {
    lappend ids $row(id)
}

puts "$pid: starting $count trials"

set idcount [llength $ids]
foreach id $ids {
    set idfound($id) 0
    set idwant($id) 0
}

set jlast 0
for {set i 0} {$i < $count} {incr i} {
    set n [expr {int(rand() * $idcount)}]
    set id [lindex $ids $n]
    set comp {}
    lappend comp [list = id $id]
    incr idwant($id)
    set found 0
    r search -compare $comp -key k -code {
	incr idfound($id)
	incr found
    }
    if {$found != 1} {
	lappend odds($id) [list $i $found]
    }
    # sleep 1ms approx 1 in 100 times
    set sleep [expr {int(rand() * 100)}]
    if {$sleep == 0} {
        after 1
    }
    set j [expr {($i * 10) / $count}] 
    if {$j != $jlast} {
        puts "$pid: count=$i"
	set jlast $j
    }
}

foreach id [array names idwant] {
    if {$idwant($id) != $idfound($id)} {
	puts "$pid: $id: wanted $idwant($id) found $idfound($id)"
	if [info exists odds($id)] {
	  puts "$pid: $id: details: $odds($id)"
	} else {
	  puts "$pid: $id: no oddballs found?"
	}
    }
}


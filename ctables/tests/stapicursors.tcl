#
# $Id$
#

package require st_shared

puts "Making connection"
set r [::stapi::connect shared://1616/master -build stobj]

puts "created reader $r"

puts [$r share list]
puts [$r share info]

set c [$r search -key k -array_get a -cursor #auto]

while {![$c at_end]} {
    set k [$c key]
    set a [$c array_get]
    $c next
    set orig($k) $a
    set curr($k) $a
    array set row $a
    lappend ids $row(id)
}
$c destroy
set names [array names orig]
set num [llength $names]

puts "Scanning 1000 samples"

set missed 0
for {set i 0} {$i < 1000} {incr i} {
    set n [expr {int(rand() * $num)}]
    set k [lindex $names $n]
    set old $curr($k)
    array set row $old
    set id $row(id)
    set comp {}
    lappend comp [list = id $id]
    set found 0
    set c [$r search -compare $comp -key k -array_get a -cursor #auto]
    while {![$c at_end]} {
	set k [$c key]
	set a [$c array_get]
	$c next
	if {"$a" != "$old"} {
	    #puts "changed $k : $a"
	    lappend changed($k) $id $a
	    set curr($k) $a
        }
	incr found
    }
    $c destroy
    if {!$found} {
	incr missed
    }
    if {$i % 100 == 0} {
	puts -nonewline "$found"; flush stdout
    }
    after 150
}

puts "\n\n1000 passes [llength [array names changed]] modified"

foreach id [array names idwant] {
    if {$idwant($id) != $idfound($id)} {
	puts "$id: wanted $idwant($id) found $idfound($id)"
    }
}
if {$missed} { puts "total: $missed missed" }

puts "deleting STAPI connection"

$r destroy


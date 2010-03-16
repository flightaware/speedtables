#
# $Id$
#

# Because
lappend auto_path /usr/local/lib/rivet/packages-local

package require st_shared

puts "Making connection"
set r [::stapi::connect shared://1616/master -build stobj]

puts "created reader $r"

puts [$r share list]
puts [$r share info]

$r search -key k -array_get a -code {
    set orig($k) $a
    set curr($k) $a
    array set row $a
    lappend ids $row(id)
}
set names [array names orig]
set num [llength $names]

puts "Scanning 1000000 samples"

for {set i 0} {$i < 100000} {incr i} {
    set n [expr {int(rand() * $num)}]
    set k [lindex $names $n]
    set old $curr($k)
    array set row $old
    set id $row(id)
    set comp {}
    lappend comp [list = id $id]
    set found 0
    $r search -compare $comp -key k -array_get a -code {
	if {"$a" != "$old"} {
	    lappend changed($k) $id $a
	    set curr($k) $a
        }
	incr found
    }
    if {!$found} {
       #puts "Missing $comp"
    }
    if {$i % 100 == 0} {
	#puts -nonewline "$found"; flush stdout
    }
    after 15
}

puts "1000000 passes [llength [array names changed]] modified"

puts "done"

foreach id [array names idwant] {
    if {$idwant($id) != $idfound($id)} {
	puts "$id: wanted $idwant($id) found $idfound($id)"
    }
}

puts "deleting STAPI connection"

$r destroy


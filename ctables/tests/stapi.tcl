#
# $Id$
#

# Because we need to be testing from the development version of stapi!
set dir [exec sh -c "cd ../../stapi; pwd"]
source $dir/pkgIndex.tcl

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

puts "Scanning 1000 samples"

set missing 0
for {set i 0} {$i < 1000} {incr i} {
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
       incr missing
    }
    after 15
}

puts "1000 passes [llength [array names changed]] modified"
puts "Missed $missing"

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
    $r search -compare $comp -key k -array_get a -code {
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

puts "Testing detach"

$r detach

puts "Reading from detached table"

set found 0
$r search -key k -array_get a -code {
    incr found
}

if {$found == 0} {
    error "Searching detached table failed"
}

puts "Attempting to fail access to detached table"

set error [catch {$r exists 1}]
if {!$error} {
    error "Failed to fail exists on detached table"
}

puts "deleting STAPI connection"

$r destroy


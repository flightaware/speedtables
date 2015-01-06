#!/usr/local/bin/tclsh8.5

package require speedtable

CExtension bullseye 1.0 {
    CTable Pasture {
        varstring alpha
        varstring beta indexed 1
        varstring delta
        varstring gamma indexed 1
    }

    CTable Barn {
        varstring alpha
        varstring beta indexed 1
        varstring delta
        varstring gamma
    }
}

package require Bullseye


if {1} {
    puts "using shmem"
    Pasture create mypasture master name "moo3" file "mypasture.dat" size "256M"
    Barn create mybarn master name "moo4" file "mypasture.dat" size "256M"
} else {
    puts "using mem"
    Pasture create mypasture
    Barn create mybarn
}

puts "created"

#
# Store some stuff in the two tables.
#
for {set i 0} {$i < 10000} {incr i} {
    mypasture store [list alpha alfa$i beta bravo$i delta delta$i gamma golf$i]

    if {$i % 150 == 0} {
        mybarn store [list alpha alfa$i beta bravo$i delta delta$i gamma golf$i]
    }
}

puts "inserted"

#
# Query some stuff from the two tables.
#
mybarn search -array barnrow -limit 10 -sort alpha -code {
    set count [array size barnrow]
    if {$count != 5} {
        puts "Error: wrong number of elements (was $count, expected 5)"
    }
    parray barnrow
    puts ""
}

puts info=[mypasture share info]
#puts pools=[mypasture share pools]
puts free=[mypasture share free]

#
# Test some shared storage.
#
mybarn share set alpha alfa
if {[mybarn share get alpha] != "alfa"} {
    error "mismatch1a"
}
if {[mybarn share multiget alpha] != [list "alfa"]} {
    error "mismatch1b"
}
mybarn share set beta "bovo bravo"
if {[mybarn share get beta] != "bovo bravo"} {
    error "mismatch2a"
}
if {[mybarn share multiget beta] != [list "bovo bravo"]} {
    error "mismatch2b"
}
mybarn share set delta deltalina gamma "gamma gamma gamma"
if {[mybarn share get gamma] != "gamma gamma gamma"} {
    error "mismatch3a"
}
if {[mybarn share multiget gamma] != [list "gamma gamma gamma"]} {
    error "mismatch3b"
}
if {[mybarn share multiget beta delta] != [list "bovo bravo" "deltalina"]} {
    error "mismatch4"
}



puts "done"


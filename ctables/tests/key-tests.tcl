#
# make sure the auto row ID thing is working for "$ctable store"
#
# $Id$
#

source test_common.tcl

proc dump_table {t} {
    foreach k [$t names] {
        puts "$k => [$t array_get $k]"
    }
}

source top-brands-genkey-def.tcl

if {"[t key]" != "id"} {
    error "Key should be 'id'"
}

if {"[lindex [t getprop key] 0]" != "id"} {
    error "'t getprop key' should be 'id'"
}

if {"[t makekey {id 1 rank 1 name first}]" != "1"} {
    error "Key value should be '1'"
}

set first_key [t store id 1 rank 1 name first]
if {"$first_key" != "1"} {
    error "First 'store' key should have been '1'"
}

if {[t count] != 1} {
    error "Should have one row after 'store'"
}

if {"[lindex [t get $first_key id] 0]" != "1"} {
    error "row '$first_key' should have had id 1"
}

if {"[lindex [t get $first_key rank] 0]" != "1"} {
    error "row '$first_key' should have had rank 1"
}

if {"[t store id 1 rank 3 name first]" != "$first_key"} {
    error "Key should have been '$first_key'"
}

if {"[lindex [t get $first_key rank] 0]" != "3"} {
    error "row '$first_key' should have had rank 3"
}

t search+ -compare {{in id {1}}} -key k -array a -code {lappend list "$k: [array get a]" }

if {![info exists list]} {
   puts "t count -> [t count]"
   dump_table t
   error "search+ test on 'in id {1}' no list, expected {1: rank 3 name first id 1}"
}
if {"[lindex $list 0]" != "1: rank 3 name first id 1"} {
   error "search+ test on 'in id {1}' returns $list expected {1: rank 3 name first id 1}"
}

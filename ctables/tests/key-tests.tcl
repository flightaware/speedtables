#
# make sure the auto row ID thing is working for "$ctable store"
#
# $Id$
#

source top-brands-genkey-def.tcl

if {"[t keys]" != "id name"} {
    error "Key should be 'id name'"
}

set first_key [t store id 1 rank 1 name first]
if {"$first_key" != "1 first"} {
    error "First 'store' key should have been '1 first'"
}

if {[t count] != 1} {
    error "Should have one row after 'store'"
}

if {"[lindex [t get $first_key id] 0]" != "1"} {
    error "row 0 should have had id 1"
}


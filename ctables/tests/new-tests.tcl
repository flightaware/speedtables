#
# make sure the auto row ID thing is working for "$ctable store"
#
# $Id$
#

source test_common.tcl

source top-brands-nokey-def.tcl

if {"[t store id 1 rank 1 name first]" != "0"} {
    error "First 'store' key should have been zero"
}

if {[t count] != 1} {
    error "Should have one row after 'store'"
}

if {"[lindex [t get 0 id] 0]" != "1"} {
    error "row 0 should have had id 1"
}


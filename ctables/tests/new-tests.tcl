#
# make sure the auto row ID thing is working for "$ctable new"
#
# $Id$
#

source top-brands-nokey-def.tcl

if {"[t new id 1 rank 1 name first]" != "0"} {
    error "First 'new' key should have been zero"
}

if {[t count] != 1} {
    error "Should have one row after 'new'"
}

if {"[lindex [t get 0 id] 0]" != "1"} {
    error "row 0 should have had id 1"
}


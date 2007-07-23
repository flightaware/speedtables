#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

source top-brands-nokey-def.tcl

top_brands_nokey create m master sharefile.dat

proc suck_in_top_brands_nokeys {} {
    set fp [open top-brands.tsv]
    set lastKey [m read_tabsep $fp -nokeys]
    close $fp
    if {"$lastKey" == ""} {
	error "should have returned next key value"
    }
    return $lastKey
}

set lastKey [suck_in_top_brands_nokeys]

if {[m count] != 100} {
    error "should have had 100 rows after read_tabsepping top-brands.tsv"
}

if {$lastKey != 99} {
    error "last row read was $lastKey and should have been 99"
}

suck_in_top_brands_nokeys

if {[m count] != 200} {
    error "should have had 200 rows after second read_tabsepping top-brands.tsv"
}

set lastKey [suck_in_top_brands_nokeys]

if {[m count] != 300} {
    error "should have had 300 rows after second read_tabsepping top-brands.tsv"
}

if {$lastKey != 299} {
    error "last row read was $lastKey and should have been 299"
}

if {[m get 299 id] != "polo"} {
    error "row 299's ID should have been polo"
}

m reset

if {[m count] != 0} {
    error "count should have been zero after reset"
}

if {[m get 99 id] != ""} {
    error "row 99 has something and shouldn't"
}

suck_in_top_brands_nokeys

if {[m count] != 100} {
    error "should have had 100 rows after read_tabsepping top-brands.tsv"
}

if {[m get 99 id] != "polo"} {
    error "row 99's ID should have been polo but is [t get 99 id]"
}

if {[m get 299 id] != ""} {
    error "row 299 shouldn't have had anything"
}


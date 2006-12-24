#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

source top-brands-nokey-def.tcl

proc suck_in_top_brands_nokeys {} {
    set fp [open top-brands.tsv]
    t read_tabsep $fp -nokeys
    close $fp
}

suck_in_top_brands_nokeys

if {[t count] != 100} {
    error "should have had 100 rows after read_tabsepping top-brands.tsv"
}

suck_in_top_brands_nokeys

if {[t count] != 200} {
    error "should have had 200 rows after second read_tabsepping top-brands.tsv"
}

suck_in_top_brands_nokeys

if {[t count] != 300} {
    error "should have had 300 rows after second read_tabsepping top-brands.tsv"
}

if {[t get 299 id] != "polo"} {
    error "row 299's ID should have been polo"
}

t reset

if {[t count] != 0} {
    error "count should have been zero after reset"
}

if {[t get 99 id] != ""} {
    error "row 99 has something and shouldn't"
}

suck_in_top_brands_nokeys

if {[t count] != 100} {
    error "should have had 100 rows after read_tabsepping top-brands.tsv"
}

if {[t get 99 id] != "polo"} {
    error "row 99's ID should have been polo but is [t get 99 id]"
}

if {[t get 299 id] != ""} {
    error "row 299 shouldn't have had anything"
}


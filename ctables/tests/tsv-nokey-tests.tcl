#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

source top-brands-nokey-def.tcl

proc check_value {format expected actual} {
    if {"$expected" != "$actual"} {
	error [format $format $expected $actual]
    }
}

proc suck_in_top_brands_nokeys {} {
    set fp [open top-brands.tsv]
    set lastKey [t read_tabsep $fp -nokeys]
    close $fp
    if {"$lastKey" == ""} {
	error "should have returned next key value"
    }
    return $lastKey
}

set lastKey [suck_in_top_brands_nokeys]

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 100 [t count]

check_value "Expected %s got %s for lastKey" 99 $lastKey

suck_in_top_brands_nokeys

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 200 [t count]

set lastKey [suck_in_top_brands_nokeys]

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 300 [t count]

check_value "Expected %s got %s for lastKey" 299 $lastKey

check_value "Expected %s for row 299's id, got %s" [t get 299 id] "polo"

t reset

check_value "Expected count = %s, got %s after reset" 0 [t count]

check_value "After reset, expected empty%s row 99 but got %s" "" [t get 99 id]

suck_in_top_brands_nokeys

check_value "After reset, expected %d rows, got %d, after read_tabsepping top-brands.tsv" 100 [t count]

check_value "After reset, expected %s for row 99's id, got %s" [t get 99 id] "polo"

check_value "After reset, expected empty%s row 299 but got %s" "" [t get 299 id]


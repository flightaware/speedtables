#
# $Id$
#

source test_common.tcl

set suffix _m

source top-brands-nokey-def.tcl

top_brands_nokey_m create m master file sharefile.dat

proc dump_table {} {
    m search -key k -array_get a -code { puts "$k => $a" }
}

proc check_value {format expected actual} {
    if {"$expected" != "$actual"} {
	dump_table
	error [format $format $expected $actual]
    }
}

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

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 100 [m count]

check_value "Expected %s got %s for lastKey" 99 $lastKey

suck_in_top_brands_nokeys

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 200 [m count]

set lastKey [suck_in_top_brands_nokeys]

check_value "Expected %d rows, got %d, after read_tabsepping top-brands.tsv" 300 [m count]

check_value "Expected %s got %s for lastKey" 299 $lastKey

check_value "Expected %s for row 299's id, got %s" [m get 299 id] "polo"

m reset

check_value "Expected count = %s, got %s after reset" 0 [m count]

check_value "After reset, expected empty%s row 99 but got %s" "" [m get 99 id]

suck_in_top_brands_nokeys

check_value "After reset, expected %d rows, got %d, after read_tabsepping top-brands.tsv" 100 [m count]

check_value "After reset, expected %s for row 99's id, got %s" [m get 99 id] "polo"

check_value "After reset, expected empty%s row 299 but got %s" "" [m get 299 id]

check_value "Expected %s got %s" "file sharefile.dat name m" [m attach 666]


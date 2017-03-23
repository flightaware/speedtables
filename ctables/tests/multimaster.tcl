#
# $Id$
#

source test_common.tcl

set suffix _m
set nametags {indexed 1}

source multitable.ct

nameval_m create nameval master file sharefile.dat
elements_m create elements master file sharefile.dat
anim_characters_m create characters master file sharefile.dat

nameval index create name
elements index create name
characters index create name

puts "nameval share info -> [nameval share info]"
puts "elements share info -> [elements share info]"
puts "nameval share list -> [nameval share list]"
puts stderr "nameval share list -> [nameval share list]"

foreach {elt nam sym} {
  1 Hydrogen H
  2 Helium He
  3 Lithium Li
  4 Beryllium Be
  5 Boron B
  6 Carbon C
  7 Nitrogen N
  8 Oxygen O
  9 Fluorine F
  10 Neon Ne
} {
  elements set $elt name $nam symbol $sym
}

for {set i 0} {$i < 1000} {incr i} {
  nameval set $i name name$i value value$i
}

proc dump_table {table} {
    $table search -key k -array_get a -code { puts "$k => $a" }
}

proc check_value {table format expected actual} {
    if {"$expected" != "$actual"} {
	dump_table $table
	error "$table: [format $format $expected $actual]"
    }
}

check_value elements "Expected %d rows, got %d, a" 10 [elements count]
check_value nameval "Expected %d rows, got %d, a" 1000 [nameval count]

package require ctable_server

::ctable_server::register ctable://*:1616/elements elements
::ctable_server::register ctable://*:1616/nameval nameval
::ctable_server::register ctable://*:1616/characters characters

if !$tcl_interactive { vwait die }

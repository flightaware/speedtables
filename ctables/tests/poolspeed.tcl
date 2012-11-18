#
# $Id$
#

source test_common.tcl

package require ctable_server

set suffix _m

source top-brands-nokey-def.tcl

proc suck_in_top_brands_nokeys {table} {
    set fp [open top-brands.tsv]
    set lastKey [$table read_tabsep $fp -nokeys]
    close $fp
    if {"$lastKey" == ""} {
	error "should have returned next key value"
    }
    return $lastKey
}

array set ::int_columns {
	rank	{	1	10	}
	value	{	100	200	}
}

set ::words {
  limburger gujeroo farenheit pleonasm lagrange elevator proximity
  pantechnicon foreign ramification sexton tangent tangelo boreal
  hyperactive desdemona cataract jubilant texas myrmidon agilent
  cadbury yellowcake uranium feathered waratah bunyip bandicoot
  princeton stanford ankh lamnington parsimony nathaniel misspelling
}
set nwords [llength $words]

proc random_changes {table count} {
  set names [lsort -decreasing [$table names]]
  set inames [array names ::int_columns]
  set nnames [llength $names]
  for {set loop 0} {$loop < $count} {incr loop} {
    set i [expr {int(rand() * $nnames)}]
    set key [lindex $names $i]
    set new {}
    foreach {col range} [array get ::int_columns] {
      foreach {max min} $::int_columns($col) break
      set val  [expr {int(rand() * ($max-$min)) + $min}]
      lappend new $col $val
    }
    $table set $key $new
  }
}

proc random_inserts {table count} {
  for {set loop 0} {$loop < $count} {incr loop} {
    set key [lindex $::words [expr {int(rand() * $::nwords)}]]
    append key $loop
    set new {}
    foreach col {rank value} {
      lappend new $col [expr {int(rand() * 100)}]
    }
    foreach col {id name} {
      lappend new $col [lindex $::words [expr {int(rand() * $::nwords)}]]
    }
    $table set $key $new
  }
}

t index create id
t index create rank
t index create name
t index create value

suck_in_top_brands_nokeys t

puts "private changes: [time {random_changes t 1000}]"
puts "private inserts: [time {random_inserts t 1000}]"

t destroy

top_brands_nokey_m create m master file sharefile.dat

m index create id
m index create rank
m index create name
m index create value

suck_in_top_brands_nokeys m

puts "m getprop -> [m getprop]"
puts "m share info -> [m share info]"

puts "pools: [m share pools]"
puts "public changes: [time {random_changes m 1000}]"
puts "pools: [m share pools]"
puts "public inserts: [time {random_inserts m 1000}]"
puts "pools: [m share pools]"

m destroy

for {set i 0} {$i < 16} {incr i} {

top_brands_nokey_m create t

t index create id
t index create rank
t index create name
t index create value

suck_in_top_brands_nokeys t

puts "private changes: [time {random_changes t 100000}]"
puts "private inserts: [time {random_inserts t 100000}]"

t destroy

top_brands_nokey_m create m master file sharefile.dat size [expr {64 * 1024 * 1024}]

m index create id
m index create rank
m index create name
m index create value

set l {}
if {$i & 1} {
    lappend l 8
    m share pool 8 65536 0
}
if {$i & 2} {
    lappend l 16
    m share pool 16 65536 0
}
if {$i & 4} {
   lappend l 24
   m share pool 24 65536 0
}
if {$i & 8} {
   lappend l 32
   m share pool 32 65536 0
}

suck_in_top_brands_nokeys m

puts "public changes: [time {random_changes m 100000}] pools: {$l}"
puts "public inserts: [time {random_inserts m 100000}] pools: {$l}"
puts "         pools: [m share pools]"

m destroy
}

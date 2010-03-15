#
# $Id$
#

package require ctable_server

set suffix _m

source top-brands-nokey-def.tcl


top_brands_nokey_m create m master file sharefile.dat
puts "m share info -> [m share info]"
puts "m share list -> [m share list]"

proc suck_in_top_brands_nokeys {} {
    set fp [open top-brands.tsv]
    set lastKey [m read_tabsep $fp -nokeys]
    close $fp
    if {"$lastKey" == ""} {
	error "should have returned next key value"
    }
    return $lastKey
}

m index create id
m index create rank
m index create name
m index create value

set ::lastKey [suck_in_top_brands_nokeys]

# puts "Contents"
# m search -key k -array_get a -code {puts "$k : $a"}

set delay 30
set count 1
set max 1000
if {[llength $argv] > 0} { set delay [lindex $argv 0] }
if {[llength $argv] > 1} { set count [lindex $argv 1] }
if {[llength $argv] > 2} { set max [lindex $argv 2] }


puts "==== delay=$delay count=$count max=$max"
::ctable_server::register ctable://*:1616/master m

array set ::int_columns {
	rank	{	1	10	}
	value	{	100	200	}
}

set words {
  limburger gujeroo farenheit pleonasm lagrange elevator proximity
  pantechnicon foreign ramification sexton tangent tangelo boreal
  hyperactive desdemona cataract jubilant texas myrmidon agilent
  cadbury yellowcake uranium feathered waratah bunyip bandicoot
  princeton stanford ankh lamington parsimony nathaniel misspelling
}
set nwords [llength $words]

proc random_changes {delay count max} {
  set names [lsort -decreasing [m names]]
  set inames [array names ::int_columns]
  for {set loop 0} {$loop < $count} {incr loop} {
    if {int(rand() * 5) >= 1} {
      set i [expr {int(rand() * [llength $names])}]
      set key [lindex $names $i]
      set j [expr {int(rand() * [llength $inames])}]
      set col [lindex $inames $j]
      foreach {max min} $::int_columns($col) break
      set val  [expr {int(rand() * ($max-$min)) + $min}]
      m set $key $col $val
    } else {
      incr ::lastKey
      set key $::lastKey
#      if {$key > $max} {
#	set key [expr {int( rand() * double($max) )}]
#      }
      array unset a
      foreach col {id name} {
	set a($col) [lindex $::words [expr {int(rand() * $::nwords)}]]
      }
      m search -compare [list [list = id $a(id)]] -key k -code {
	if {int(rand() * 2)} {
	  set key $k
	  unset a(id)
	} else {
	  append a(id) - $key
	}
      }
      set a(rank) 10
      set a(value) 0
      set list [array get a]
      m set $key $list
    }
  }
  after $delay random_changes $delay $count $max

#  puts [list [clock format [clock seconds]] m count [m count]]
}

proc status {delay} {
  puts "[clock format [clock seconds]] [pid]: created $::lastKey rows size=[m count]"
  after [expr $delay * 1000] status $delay
}
puts "running, delay = $delay, count=$count, max=$max, waiting for connections"
after $delay random_changes $delay $count $max
after $delay status $delay

if !$tcl_interactive { vwait die }


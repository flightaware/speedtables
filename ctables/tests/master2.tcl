#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

source test_common.tcl

package require ctable_server

set suffix _m

source top-brands-nokey-def.tcl

top_brands_nokey_m create m master file sharefile.dat

# memory active memdebug_start.txt
# memory onexit memdebug_end.txt
# memory trace on

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

suck_in_top_brands_nokeys

# puts "Contents"
# m search -key k -array_get a -code {puts "$k : $a"}

variable last_set

proc random_changes {} {
  variable last_set
  set names [m names]
  set i [expr {int(rand() * [llength $names])}]
  set key [lindex $names $i]
  set val [expr {int(rand() * 100) + 100}]
  # puts [list m set $key value $val]
  m set $key value $val
  set last_set [m array_get $key]
}

for {set i 0} {$i < 1000} {incr i} {
  random_changes
}

foreach {col val} $last_set {
  puts "Testing search -compare {{= $col $val}}"
  set found 0
  m search -compare [list [list = $col $val]] -array r -code {
    set missed 0
    foreach {rcol rval} $last_set {
      if {![info exists r($rcol)] || "$r($rcol)" != "$rval"} {
	incr missed
	break
      }
    }
    if {!$missed} { incr found }
  }
  if {!$found} {
    error "No matching row for {{= $col $val}}"
  }
}


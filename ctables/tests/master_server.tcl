#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_server

set suffix _m

source top-brands-nokey-def.tcl


top_brands_nokey_m create m master file sharefile.dat

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

set delay 30
set count 1
if {[llength $argv] > 0} { set delay [lindex $argv 0] }
if {[llength $argv] > 1} { set count [lindex $argv 1] }

::ctable_server::register ctable://*:1616/master m

proc random_changes {delay count} {
  set names [m names]
  for {set loop 0} {$loop < $count} {incr loop} {
    set i [expr {int(rand() * [llength $names])}]
    set key [lindex $names $i]
    m set $key value [expr {int(rand() * 100) + 100}]
  }
  after $delay random_changes $delay $count
}
puts "running, delay = $delay, count=$count, waiting for connections"
after $delay random_changes $delay $count

if !$tcl_interactive { vwait die }


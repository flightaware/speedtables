#
# check that clean and dirty fields work
#
# $Id$
#

source test_common.tcl

package require ctable

source searchtest-def.tcl

source dumb-data.tcl

puts "Testing dirty and clean"

set dirty_count 0
set dirty_keys {}
t search -compare {{= _dirty 1}} -key k -code {
  incr dirty_count
  lappend dirty_keys $k
}

set expected [t count]

if {$dirty_count != $expected} {
  error "Expected $expected dirty rows got $dirty_count"
}

set keys [lsort [t names]]
set dirty_keys [lsort $dirty_keys]

if {$keys != $dirty_keys} {
  error "Expected '$keys' got '$dirty_keys'
}

t clean

set dirty_count [t search -compare {{= _dirty 1}} -countOnly 1]

if {$dirty_count != 0} {
  error "Expected 0 dirty rows got $dirty_count"
}

t set meatwad coolness -100
t set shake coolness -100

set dirty_count 0
set dirty_keys {}
t search -compare {{= _dirty 1}} -key k -code {
  incr dirty_count
  lappend dirty_keys $k
}

if {$dirty_count != 2} {
  error "Expected 2 dirty rows got $dirty_count"
}

set dirty_keys [lsort $dirty_keys]
if {$dirty_keys != "meatwad shake"} {
  error "Expected dirty keys to equal 'meatwad shake' got $dirty_keys"
}

puts "read_tabsep test"
t clean

set fp [open clean-data.tsv r]
t read_tabsep $fp -with_field_names
close $fp

set dirty_count [t search -compare {{= _dirty 1}} -countOnly 1]

if {$dirty_count != 2} {
  error "Expected 2 dirty rows got $dirty_count"
}

puts "read_tabsep -dirty test"
t clean

set fp [open clean-data.tsv r]
t read_tabsep $fp -with_field_names -dirty
close $fp

set dirty_count [t search -compare {{= _dirty 1}} -countOnly 1]

if {$dirty_count != 4} {
  error "Expected 4 dirty rows got $dirty_count"
}

puts "OK"

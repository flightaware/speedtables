#
# check that clean and dirty fields work
#
# $Id$
#

source test_common.tcl

package require ctable

source searchtest-def.tcl

source dumb-data.tcl

set dirty_count 0
set dirty_keys {}
t search -compare {{= _dirty 1}} -key k -code {
  incr dirty_count
  lappend dirty_keys $k
}

if {$dirty_count != 31} {
  error "Expected 31 dirty rows got $dirty_count"
}

t clean

set dirty_count 0
set dirty_keys {}
t search -compare {{= _dirty 1}} -key k -code {
  incr dirty_count
  lappend dirty_keys $k
}

if {$dirty_count != 0} {
  error "Expected 0 dirty rows got $dirty_count"
}

set show "ATHF"
set home "Next To Carl"
 
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


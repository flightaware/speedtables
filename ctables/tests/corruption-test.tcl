#
# incr test - test ctable "incr" method
#
# $Id$
#

source test_common.tcl

source bug_tables.ct

package require Bug_tables 1.0

Foo create fooInstance
fooInstance index create bar

for {set i 0} {$i < 10000} {incr i} {
  set key [expr {int(rand() * 5)}]
  if {rand() > 0.9} {
    set value ""
  } else {
    set value "N12345"
  }

  fooInstance set $key bar $value
}


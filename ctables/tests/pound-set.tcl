#
#
#
#
#
#
# $Id$
#

source dumb-data.tcl

for {set i 0} {$i < 1000000} {incr i} {
    t set b name "Prisoner $i" address "Cell $i"
}


puts [exec ps alwwx | grep tclsh]

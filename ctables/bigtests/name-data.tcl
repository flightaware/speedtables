#
# test ctables search routine
#
# $Id$
#

source nametest-extension.tcl

puts "read tabsep database into ctable"
set fp [open test-data.txt]
puts [time {n read_tabsep $fp}]
close $fp

puts "[n count] records loaded into ctable n"

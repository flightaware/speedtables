#
# test ctables search routine
#
# $Id$
#

source nametest-extension.tcl

n index create name

puts "read tabsep database into ctable with simultaneous index generation"
set fp [open names.txt]
puts [time {n read_tabsep $fp}]
close $fp

puts "[n count] records loaded into ctable n"

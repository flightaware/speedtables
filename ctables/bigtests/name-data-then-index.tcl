#
# test ctables search routine
#
# $Id$
#

source nametest-extension.tcl

puts "read tabsep database into ctable"
set fp [open names.txt]
puts [time {n read_tabsep $fp}]
close $fp
puts "[n count] records loaded into ctable n"

puts "generate index"
puts [time {n index create name}]
puts "done"

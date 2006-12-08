#
# test indexes
#
# $Id$
#

source nametest-extension.tcl

source name-data.tcl

puts -nonewline "creating index..."; flush stdout
n index create name
puts "done."

puts "index count [n index count name]"
puts "row count [n count]"

time {n search -compare {{match name "*bernadine piersol*"}} -write_tabsep stdout}



#
#
#
#
#
# $Id$
#


source dumb-data.tcl

t index create name

t index dump name

puts "\n\nadding new karl name Carl (dup)\n\n"

t set karl name Carl

t index dump name

puts "\n\deleting carl\n\n"

t delete carl

t index dump name

puts "\n\searching for Carl*\n\n"

t search+ -compare {{range name Carl Carm}} -write_tabsep stdout


puts "\n\deleting karl\n\n"

t delete karl

t index dump name


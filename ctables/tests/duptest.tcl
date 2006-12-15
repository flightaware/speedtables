#
#
#
#
#
# $Id$
#


source dumb-data.tcl

t index create name

#t index dump name

puts "\n\nadding new karl name Carl (dup)\n\n"

t set karl name Carl

#t index dump name

puts "\n\deleting carl\n\n"

t delete carl

#t index dump name

puts "\n\searching for Carl*\n\n"

t search+ -compare {{range name Carl Carm}} -write_tabsep stdout


puts "\n\deleting karl\n\n"

t delete karl

#t index dump name

puts "\n\nsearching C to D\n\n"

t search+ -compare {{range name C D}} -write_tabsep stdout

puts "\n\nsearching C to D the old way\n\n"
t search -compare {{>= name C} {< name D}} -write_tabsep stdout

puts "\n\nsearching A to B\n\n"

t search+ -compare {{range name A B}} -write_tabsep stdout

puts "\n\nsearching A to B the old way\n\n"
t search -compare {{>= name A} {< name B}} -write_tabsep stdout


puts "\n\nsearching T to Z\n\n"

t search+ -compare {{range name T Z}} -write_tabsep stdout

puts "\n\nsearching T to Z the old way\n\n"
t search -compare {{>= name T} {< name Z}} -sort name -write_tabsep stdout


puts "\n\nsearching Coroner to Triana\n\n"

t search+ -compare {{range name Coroner Triana}} -write_tabsep stdout

puts "\n\nsearching Coroner to Triana the old way\n\n"
t search -compare {{>= name Coroner} {< name Triana}} -sort name -write_tabsep stdout



#
# match tests -- tests searching
#
# $Id$
#

source dumb-data.tcl


puts "matching *VENTURE*"
t search -fields name -compare {{match name *VENTURE*}} -write_tabsep stdout
puts ""

puts "case-matching *VENTURE*"
t search -fields name -compare {{match_case name *VENTURE*}} -write_tabsep stdout
puts ""

puts "case-matching *Tri*"
t search -fields name -compare {{match_case name *Tri*}} -write_tabsep stdout
puts ""




source dumb-data.tcl


puts "matching *venture*"
t search -compare {{match name *venture*}} -write_tabsep stdout
puts ""

puts "case-matching *venture*"
t search -compare {{match_case name *venture*}} -write_tabsep stdout
puts ""

puts "case-matching *Tri*"
t search -compare {{match_case name *Tri*}} -write_tabsep stdout
puts ""


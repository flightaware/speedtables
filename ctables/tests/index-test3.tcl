

source searchtest-def.tcl

source dumb-data.tcl

t index create name

puts "plain search+"
t search+ -write_tabsep stdout
puts ""

puts "search+ with a compare function"
t search+ -compare {{range name D Hoop}} -write_tabsep stdout
puts ""


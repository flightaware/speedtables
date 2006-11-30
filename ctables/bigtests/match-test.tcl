

source name-data.tcl


proc test1 {} {
    puts "matching *bernadine piersol*"

    n search -compare {{match name "*bernadine piersol*"}} -write_tabsep stdout
    puts ""
}

puts [time test1]
puts [time test1]

proc test2 {} {
    puts "matching *bernadine*piersol*"

    n search -compare {{match name "*bernadine*piersol*"}} -write_tabsep stdout
    puts ""
}

puts [time test2]
puts [time test2]



source name-data.tcl

source cputime.tcl


proc test1 {} {
    puts "matching *bernadine piersol*"

    n search -compare {{match name "*bernadine piersol*"}} -write_tabsep stdout
    puts ""
}

puts [cputime test1]
puts [cputime test1]

proc test2 {} {
    puts "matching *bernadine*piersol*"

    n search -compare {{match name "*bernadine*piersol*"}} -write_tabsep stdout
    puts ""
}

puts [cputime test2]
puts [cputime test2]



source name-data.tcl


proc test1 {} {
    puts "matching *bernadine piersol*"

    n search -compare {{match name "*bernadine piersol*"}} -write_tabsep stdout
    puts ""
}

time test1


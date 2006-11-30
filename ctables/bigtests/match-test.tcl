

source name-data.tcl

#source cputime.tcl
proc cputime {cmd} {
    time $cmd 10
}


proc test1 {} {
    puts "matching *bernadine piersol*"

    n search -compare {{match name "*bernadine piersol*"}} -write_tabsep stdout
}

puts [cputime test1]

proc test2 {} {
    puts "matching *bernadine*piersol*"

    n search -compare {{match name "*bernadine*piersol*"}} -write_tabsep stdout
}

puts [cputime test2]

proc test3 {} {
    puts "matching *bernadine piersol* count only"

    puts [n search -compare {{match name "*bernadine piersol*"}} -countOnly 1]
}

puts [cputime test3]

proc test4 {} {
    puts "\nmatching *piersol* count only"
    puts [n search -compare {{match name "*piersol*"}} -countOnly 1]

}

puts [cputime test4]

proc test5 {} {
    puts "\nmatching *piersol* -write_tabsep /dev/null"
    set ofp [open /dev/null w]
    puts [n search -compare {{match name "*piersol*"}} -write_tabsep $ofp]
    close $ofp
}

puts [cputime test5]

proc test6 {} {
    puts "\nmatching *piersol* with fairly empty -code loop"
    puts [n search -compare {{match name "*piersol*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test6]

proc test7 {} {
    puts "\nmatching Bernadine* with fairly empty -code loop"
    puts [n search -compare {{match name "Bernadine*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test7]

proc test8 {} {
    puts "\nmatching *Bernadine* with fairly empty -code loop"
    puts [n search -compare {{match name "*Bernadine*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test8]

proc test9 {} {
    puts "\nmatching *Bernadine*Piersol with fairly empty -code loop"
    puts [n search -compare {{match name "*Bernadine*Piersol*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test9]

# we don't normally need to destroy but it helps for memory debugging
n destroy

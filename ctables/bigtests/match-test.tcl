#
# do some match testing on ctables
#
# $Id$
#

source nametest-extension.tcl

source cputime.tcl

puts "loading data"
puts [cputime {source name-data.tcl}]

proc test1 {} {
    puts "matching *lehenbauer* (unanchored search)"

    n search -compare {{match name "*lehenbauer*"}} -write_tabsep stdout
}

puts [cputime test1]

proc test2 {} {
    puts "matching *Sylvester*Bakerville* (beyond unanchored search)"

    n search -compare {{match name "*Sylvester*Bakerville*"}} -write_tabsep stdout
}

puts [cputime test2]

proc test3 {} {
    puts "matching *lehenbauer* count only (unanchored)"

    puts [n search -compare {{match name "*lehenbauer*"}} -countOnly 1]
}

puts [cputime test3]

proc test3a {} {
    puts "notmatching *lehenbauer* count only"

    puts [n search -compare {{notmatch name "*lehenbauer*"}} -countOnly 1]
}

puts [cputime test3a]

proc test3b {} {
    puts "matching *bauer* count only"

    puts [n search -compare {{match name "*bauer*"}} -countOnly 1]
}

puts [cputime test3b]

proc test3b1 {} {
    puts "notmatch *bauer* count only"

    puts [n search -compare {{notmatch name "*bauer*"}} -countOnly 1]
}

puts [cputime test3b1]

proc test3b2 {} {
    puts "match_case *Bauer* count only"

    puts [n search -compare {{match_case name "*Bauer*"}} -countOnly 1]
}

puts [cputime test3b2]

proc test3b3 {} {
    puts "notmatch_case *Bauer* count only"

    puts [n search -compare {{notmatch_case name "*Bauer*"}} -countOnly 1]
}

puts [cputime test3b3]

proc test3c {} {
    puts "notcase_matching *Lehenbauer* count only"

    puts [n search -compare {{notmatch_case name "*Lehenbauer*"}} -countOnly 1]
}

puts [cputime test3c]

proc test3d {} {
    puts "notcase_matching *lehenbauer* count only"

    puts [n search -compare {{notmatch_case name "*lehenbauer*"}} -countOnly 1]
}

proc test3e {} {
    puts "case_matching Karl* count only"

    puts [n search -compare {{match_case name "Karl*"}} -countOnly 1]
}

puts [cputime test3e]

proc test3f {} {
    puts "notcase_matching Karl* count only"

    puts [n search -compare {{notmatch_case name "Karl*"}} -countOnly 1]
}

puts [cputime test3f]

proc test4 {} {
    puts "\nmatching *Disney* count only"
    puts [n search -compare {{match name "*Disney*"}} -countOnly 1]

}

puts [cputime test4]

proc test5 {} {
    puts "\nmatching *Disney* -write_tabsep /dev/null"
    set ofp [open /dev/null w]
    puts [n search -compare {{match name "*Disney*"}} -write_tabsep $ofp]
    close $ofp
}

puts [cputime test5]

proc test6 {} {
    puts "\nmatching *Wozniak* with fairly empty -code loop"
    puts [n search -compare {{match name "*Wozniak*"}} -key key -array_get_with_nulls data -code {}]

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
    puts "\nmatching *Bernadine*Rottinghous with fairly empty -code loop"
    puts [n search -compare {{match name "*Bernadine*Rottinghous*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test9]

proc test10 {} {
    puts "\n= Tatiana lehenbauer with fairly empty -code loop"
    puts [n search -compare {{= name "Tatiana Lehenbauer"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test10]



# we don't normally need to destroy but it helps for memory debugging
#n destroy


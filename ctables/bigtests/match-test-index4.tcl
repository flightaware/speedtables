#
# This demonsrates the difference in performance that simply having better
# locality between the skip list nodes and their corresponding table rows
# by mallocing them near the same point in time, as oppposed to 
# match-test-index2.tcl, which reads in the million-row table and THEN
# generates an index.
#
# In this test we generate two indexes, one on longitude and one on name
# and exercise both of them.
#
# This incorporates the longitude tests of range-test.tcl
#
# $Id$
#

source nametest-extension.tcl

source cputime.tcl

puts "creating two indexes on the fly while importing a million rows"
n index create name
n index create longitude

puts [cputime {source name-data.tcl}]

proc test1 {} {
    puts "matching *lehenbauer*"

    n search -compare {{match name "*lehenbauer*"}} -write_tabsep stdout
}

puts [cputime test1]

proc test1b {} {
    set compare {{in name "Shemika Lehenbauer" "Roberta Lehenbauer" "Shemeka Lehenbauer" "Tamatha Lehenbauer" "Teofila Lehenbauer" "Palma Lehenbauer" "Rene Lehenbauer" "Rosie Lehenbauer" "Tayna Lehenbauer" "Tarsha Lehenbauer" "Petronila Lehenbauer" "Shavon Lehenbauer" "Sharron Lehenbauer" "Tatiana Lehenbauer"}}
    puts "'in' looking for $compare"

    n search+ -compare $compare -write_tabsep stdout
}

puts [cputime test1b]

proc test2 {} {
    puts "matching *Sylvester*Bakerville*"

    n search -compare {{match name "*Sylvester*Bakerville*"}} -write_tabsep stdout
}

puts [cputime test2]

proc test3 {} {
    puts "matching *lehenbauer* count only"

    puts [n search -compare {{match name "*lehenbauer*"}} -countOnly 1]
}

puts [cputime test3]

proc test4 {} {
    puts "\nmatching *Disney* count only"
    puts [n search -compare {{match name "*Disney*"}} -countOnly 1]

}

puts [cputime test4]

proc test5 {} {
    puts "\nmatching *Disney* -write_tabsep /dev/null"
    set ofp [open /dev/null w]
    puts [n search+ -compare {{match name "*Disney*"}} -write_tabsep $ofp]
    close $ofp
}

puts [cputime test5]

proc test6 {} {
    puts "\nmatching *Wozniak* with fairly empty -code loop"
    puts [n search -compare {{match name "*Wozniak*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test6]

proc test7 {} {
    puts "\nmatching Bernadine* with count"
    puts [n search -compare {{match name "Bernadine*"}} -countOnly 1]

}

puts [cputime test7]

proc test8 {} {
    puts "\nranging Bernadine with count"
    puts [n search+ -compare {{range name Bernadine Bernadinf}} -key key -countOnly 1]

}

puts [cputime test8]

proc test9 {} {
    puts "\nmatching *Bernadine* with fairly empty -code loop"
    puts [n search -compare {{match name "*Bernadine*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test9]

proc test10 {} {
    puts "\nmatching *Bernadine*Rottinghous with fairly empty -code loop"
    puts [n search -compare {{match name "*Bernadine*Rottinghous*"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test10]

proc test11 {} {
    puts "\n= Tatiana Lehenbauer with fairly empty -code loop"
    puts [n search+ -compare {{= name "Tatiana Lehenbauer"}} -key key -array_get_with_nulls data -code {}]

}

puts [cputime test11]


#
# test matching and ranging against a floating point hoked-up 
#  latitude and longitude
#
#
proc test1 {} {
    puts "matching lon/lat box -95.57 to -95.56, 29.76 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.57} {< longitude -95.56} {>= latitude 29.76} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test1]

proc test2 {} {
    puts "matching lon/lat box -95.57 to -95.56, 29.76 to 29.77 with search+"

    puts [n search+ -compare {{>= longitude -95.57} {< longitude -95.56} {>= latitude 29.76} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test2]

proc test3 {} {
    puts "ranging lon, lon/lat box -95.57 to -95.56, 29.76 to 29.77 with search+"

    puts [n search+ -compare {{range longitude -95.57 -95.56} {>= latitude 29.76} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test3]


proc test4 {} {
    puts "matching lon/lat box -95.575 to -95.56, 29.765 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.575} {< longitude -95.56} {>= latitude 29.765} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test4]

proc test5 {} {
    puts "matching lon/lat box -95.575 to -95.56, 29.765 to 29.77, with search+"

    puts [n search+ -compare {{>= longitude -95.575} {< longitude -95.56} {>= latitude 29.765} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test5]

proc test6 {} {
    puts "ranging lon/lat box -95.575 to -95.56, 29.765 to 29.77, with search+"

    puts [n search+ -compare {{range longitude -95.575 -95.56} {>= latitude 29.765} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test6]


proc test7 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.579} {< longitude -95.56} {>= latitude 29.769} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test7]

proc test8 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+"

    puts [n search+ -compare {{>= longitude -95.579} {< longitude -95.56} {>= latitude 29.769} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test8]

proc test9 {} {
    puts "ranging lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+"

    puts [n search+ -compare {{range longitude -95.579 -95.56} {>= latitude 29.769} {< latitude 29.77}} -countOnly 1]
}

puts [cputime test9]


proc test10 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+ limit 10"

    puts [n search+ -compare {{>= longitude -95.579} {< longitude -95.56} {>= latitude 29.769} {< latitude 29.77}} -write_tabsep stdout -limit 10]
}

puts [cputime test10]

proc test11 {} {
    puts "ranging lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+ limit 10"

    puts [n search+ -compare {{range longitude -95.579 -95.56} {>= latitude 29.769} {< latitude 29.77}} -write_tabsep stdout -limit 10]
}

puts [cputime test11]


proc test12 {} {
    puts "search counting lon -95.57 to -95.5695"

    puts [n search -compare {{>= longitude -95.57} {< longitude -95.5695}} -countOnly 1]
}

puts [cputime test12]

proc test13 {} {
    puts "search+ with range counting lon -95.57 to -95.5695"

    puts [n search+ -compare {{range longitude -95.57 -95.5695}} -countOnly 1]
}

puts [cputime test13]


proc test14 {} {
    puts "search+ with range counting lon -95.57 to -95.5695 and second range"

    puts [n search+ -compare {{range longitude -95.57 -95.5695} {range latitude 0 180}} -countOnly 1]
}

puts [cputime test14]




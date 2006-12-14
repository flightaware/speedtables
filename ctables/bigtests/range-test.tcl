#
# test matching and ranging against a floating point hoked-up 
#  latitude and longitude
#
#
#
# $Id$
#

source nametest-extension.tcl

puts "creating longitude index on the fly"
n index create longitude

source name-data.tcl

#source cputime.tcl
proc cputime {x} {
    return [time $x]
}


proc test1 {} {
    puts "matching lon/lat box -95.57 to -95.56, 29.76 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.57} {<= longitude -95.56} {>= latitude 29.76} {<= latitude 29.77}} -countOnly 1]
}

puts [time test1]

proc test2 {} {
    puts "matching lon/lat box -95.57 to -95.56, 29.76 to 29.77 with search+"

    puts [n search+ -compare {{>= longitude -95.57} {<= longitude -95.56} {>= latitude 29.76} {<= latitude 29.77}} -countOnly 1]
}

puts [time test2]

proc test3 {} {
    puts "ranging lon, lon/lat box -95.57 to -95.56, 29.76 to 29.77 with search+"

    puts [n search+ -compare {{range longitude -95.57 -95.56} {>= latitude 29.76} {<= latitude 29.77}} -countOnly 1]
}

puts [time test3]


proc test4 {} {
    puts "matching lon/lat box -95.575 to -95.56, 29.765 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.575} {<= longitude -95.56} {>= latitude 29.765} {<= latitude 29.77}} -countOnly 1]
}

puts [time test4]

proc test5 {} {
    puts "matching lon/lat box -95.575 to -95.56, 29.765 to 29.77, with search+"

    puts [n search+ -compare {{>= longitude -95.575} {<= longitude -95.56} {>= latitude 29.765} {<= latitude 29.77}} -countOnly 1]
}

puts [time test5]

proc test6 {} {
    puts "ranging lon/lat box -95.575 to -95.56, 29.765 to 29.77, with search+"

    puts [n search+ -compare {{range longitude -95.575 -95.56} {>= latitude 29.765} {<= latitude 29.77}} -countOnly 1]
}

puts [time test6]


proc test7 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, standard search"

    puts [n search -compare {{>= longitude -95.579} {<= longitude -95.56} {>= latitude 29.769} {<= latitude 29.77}} -countOnly 1]
}

puts [time test7]

proc test8 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+"

    puts [n search+ -compare {{>= longitude -95.579} {<= longitude -95.56} {>= latitude 29.769} {<= latitude 29.77}} -countOnly 1]
}

puts [time test8]

proc test9 {} {
    puts "ranging lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+"

    puts [n search+ -compare {{range longitude -95.579 -95.56} {>= latitude 29.769} {<= latitude 29.77}} -countOnly 1]
}

puts [time test9]


proc test10 {} {
    puts "matching lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+ limit 10"

    puts [n search+ -compare {{>= longitude -95.579} {<= longitude -95.56} {>= latitude 29.769} {<= latitude 29.77}} -write_tabsep stdout -limit 10]
}

puts [time test10]

proc test11 {} {
    puts "ranging lon/lat box -95.579 to -95.56, 29.769 to 29.77, with search+ limit 10"

    puts [n search+ -compare {{range longitude -95.579 -95.56} {>= latitude 29.769} {<= latitude 29.77}} -write_tabsep stdout -limit 10]
}

puts [time test11]



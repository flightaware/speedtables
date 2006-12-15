#
# test seeing if the reset method causes memory corruption.
#
# $Id$
#

source nametest-extension.tcl

puts "\n\nloading the table...\n"

source name-data.tcl

puts "done.  resetting..."

n reset

puts "done."

puts "\nreloading the table...\n"

source name-data.tcl

puts "done."


#source cputime.tcl
proc cputime {x} {
    return [time $x]
}

proc test1 {} {
    puts "matching *lehenbauer*"

    n search -compare {{match name "*lehenbauer*"}} -write_tabsep stdout
}

puts [cputime test1]

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


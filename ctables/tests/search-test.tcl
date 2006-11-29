#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension searchtest 1.0 {

CTable testTable {
    varstring name
    varstring address
    int hipness
    int coolness
    double karma
    boolean realness
    boolean aliveness
}

}

package require Searchtest

testTable create t


t set a name Hendrix address "Heaven" coolness 100 realness 1 aliveness 0 karma 5
t set b name Joplin address "Heaven" coolness 60 realness 1 aliveness 0 karma 5
t set c name Brock address "Venture Compound" coolness 50 realness 0 aliveness 1
t set d name Hank address "Venture Compound" coolness 0 realness 0 aliveness 1
t set d name "Doctor Jonas Venture" address "Venture Compound" coolness 10 realness 0 aliveness 0
t set e name "Doctor Orpheus" address "Venture Compound" coolness 0 realness 0 aliveness 1
t set f name "Triana" address "Venture Compound" coolness 50 realness 0 aliveness 1
t set g name "Doctor Girlfriend" address "The Cocoon" coolness 70 realness 0 aliveness 1
t set h name "The Monarch" address "The Cocoon" coolness 20 realness 0 aliveness 1
t set i name "Number 21" address "The Cocoon" coolness 10 realness 0 aliveness 1
t set j name "Meatwad" address "Next-door to Carl" coolness 10 realness 0 aliveness 1
t set k name "Master Shake" address "Next-door to Carl" coolness 15 realness 0 aliveness 1
t set l name "Frylock" address "Next-door to Carl" coolness 5 realness 0 aliveness 1

puts "search with write_tabsep / notnull karma"
t search -write_tabsep stdout -compare {{notnull karma}}
puts ""

puts "search with write_tabsep / null karma and coolness >= 25 / sort desc on coolness"
t search -write_tabsep stdout -compare {{null karma} {>= coolness 25}} -sort -coolness
puts ""

puts "search with write_tabsep / sort on coolness / descending / limit 1"
t search -write_tabsep stdout -sort -coolness -limit 1
puts ""


puts "search with implicit fields, tabsep, not realness and not aliveness"
t search -write_tabsep stdout -compare {{false realness} {false aliveness}}
puts ""

puts "search with write_tabsep / sort on name / limit 5"
t search -write_tabsep stdout -sort name -limit 5
puts ""

puts "search with write_tabsep / sort on name / descending / limit 5"
t search -write_tabsep stdout -sort -name -limit 5
puts ""

puts "search with write_tabsep / sort on name / descending / offset 4 / limit 5"
t search -write_tabsep stdout -sort -name -limit 5 -offset 4
puts ""

puts "search with implicit fields, tabsep, coolness >= 50"
t search -write_tabsep stdout -compare {{>= coolness 50}}
puts ""


puts "search with explicit fields, tabsep, coolness >= 50"
t search -write_tabsep stdout -fields {name coolness} -compare {{>= coolness 50}}
puts ""

puts "search with code body"
t search -key key -get list -code {puts "$key -> $list"}
puts ""

puts "search with code body / explicit fields"
t search -key key -get list -fields {name address karma} -code {puts "$key -> $list"}
puts ""

puts "search with code body / array get"
t search -key key -array_get list -code {puts "$key -> $list"}
puts ""

puts "search with code body / array get with nulls"
t search -key key -array_get_with_nulls list -code {puts "$key -> $list"}
puts ""

puts "search with straight write_tabsep"
t search -write_tabsep stdout
puts ""

puts "search with write_tabsep / explicit fields"
t search -write_tabsep stdout -fields {name address hipness coolness karma}
puts ""

puts "search with write_tabsep / explicit fields / sort on name"
t search -write_tabsep stdout -fields {name address hipness coolness karma} -sort name
puts ""

puts "search with write_tabsep / explicit fields / sort on name / coolness >= 50"
t search -write_tabsep stdout -fields {name address hipness coolness karma} -sort name -compare {{>= coolness 50}}
puts ""

puts "search with write_tabsep / explicit fields / sort on name / coolness >= 50 / limit 2"
t search -write_tabsep stdout -fields {name address hipness coolness karma} -sort name -compare {{>= coolness 50}} -limit 2
puts ""

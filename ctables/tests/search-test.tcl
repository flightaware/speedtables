#
# test ctables search routine
#
# $Id$
#

package require ctable

source dumb-data.tcl

#name home show dad alive gender age coolness

puts "search with write_tabsep / notnull dad"
t search -write_tabsep stdout -compare {{notnull dad}}
puts ""

puts "search with write_tabsep / null dad and age >= 25 / sort desc on age"
t search -write_tabsep stdout -compare {{null dad} {>= age 25}} -sort -age
puts ""

puts "search with write_tabsep / sort on coolness / descending / limit 1"
t search -write_tabsep stdout -sort -coolness -limit 1
puts ""


puts "search with implicit fields, tabsep, not alive"
t search -write_tabsep stdout -compare {{false alive}}
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
t search -key key -get list -fields {name show home} -code {puts "$key -> $list"}
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
t search -write_tabsep stdout -fields {name home gender coolness dad}
puts ""

puts "search with write_tabsep / explicit fields / sort on name"
t search -write_tabsep stdout -fields {name home coolness alive} -sort name
puts ""

puts "search with write_tabsep / explicit fields / sort on name / coolness >= 50"
t search -write_tabsep stdout -fields {name home show coolness gender} -sort name -compare {{>= coolness 50}}
puts ""

puts "search with write_tabsep / explicit fields / sort on name / coolness >= 50 / limit 2"
t search -write_tabsep stdout -fields {name age} -sort name -compare {{>= coolness 50}} -limit 2
puts ""

puts "search with write_tabsep / no fields / sort on name / coolness >= 50 / limit 2"
t search -write_tabsep stdout -fields {} -sort name -compare {{>= coolness 50}} -limit 2
puts ""


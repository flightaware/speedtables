#
#
#
#
#
# $Id$
#

source top-brands-def.tcl

proc suck_in_top_brands {args} {
    set fp [open top-brands.tsv]
    eval t read_tabsep $fp $args
    close $fp
}

puts "first suck"
suck_in_top_brands

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

puts "second suck"
suck_in_top_brands

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}
puts "finished"


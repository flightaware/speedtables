#
#
#
#
#
# $Id$
#

source test_common.tcl

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

puts "write test"
proc check_first_line {list {expected ""}} {
   set fp [open /tmp/top_brands.tsv w]
   eval [concat [list t search -write_tabsep $fp] $list]
   close $fp
   set fp [open /tmp/top_brands.tsv r]
   if ![gets $fp line] {
      error "no data written to /tmp/top_brands.tsv"
   }
   close $fp
   if {"$expected" != "" && "$line" != "$expected"} {
      regsub -all "\t" $line {\t} tline
      regsub -all "\t" $expected {\t} texpected
      error "bad data in /tmp/top_brands.tsv\n\texpected $texpected\n\tgot $tline"
   }
}

check_first_line {} ""
check_first_line {-sort rank} "coke\t1\tCoca-Cola\t67394"
check_first_line {-sort name} "aol\t82\tAOL\t3248"
check_first_line {-with_field_names 1 -fields {name value}} "_key\tname\tvalue"

puts "read/write test"
t reset
set fp [open /tmp/top_brands.tsv r]
t read_tabsep $fp -with_field_names
close $fp

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

if {"[t get aol]" != "{} AOL 3248"} {
    error "got [list [t get aol]] expected {{} AOL 3248}"
}

puts "tab string test"
check_first_line {-with_field_names 1 -fields {name value} -tab "XXX"} "_keyXXXnameXXXvalue"

set fp [open /tmp/top_brands.tsv r]
t read_tabsep $fp -tab "XXX" -with_field_names
close $fp

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

if {"[t get aol]" != "{} AOL 3248"} {
    error "got [list [t get aol]] expected {{} AOL 3248}"
}


puts "second suck"
suck_in_top_brands

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

puts "reorder test"
set fp [open /tmp/wonky_brands.tsv w]
t search -write_tabsep $fp -with_field_names 1 -fields {name rank value}
close $fp

t reset

set fp [open /tmp/wonky_brands.tsv r]
t read_tabsep $fp -with_field_names
close $fp

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

if {"[t get aol]" != "82 AOL 3248"} {
    error "got [list [t get aol]] expected {82 AOL 3248}"
}

puts "finished"


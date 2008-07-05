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

puts "nocomplain test"
# gen up a dummy file
set fp [open /tmp/extra_brands.tsv w]
puts $fp "_key\tname\tcharm\trank\tserial\tvalue"
t search -key k -array_with_nulls a -code {
	puts $fp "$k\t$a(name)\t[expr {int(rand() * 10.0 + 1)}]\t$a(rank)\t[clock seconds]\t$a(value)"
}
close $fp
t reset

set fp [open /tmp/extra_brands.tsv r]
t read_tabsep $fp -nocomplain -with_field_names
close $fp

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

if {"[t get aol]" != "82 AOL 3248"} {
    error "got [list [t get aol]] expected {82 AOL 3248}"
}

puts "quoting test {-quote uri}"

t set tab name "tab\there" rank 66 value 66
t set newline name "new\nline" rank 66 value 66

set fp [open /tmp/quote_test.tsv w]
t search -quote uri -write_tabsep $fp -with_field_names 1
close $fp

t reset

set fp [open /tmp/quote_test.tsv r]
t read_tabsep $fp -quote uri -with_field_names
close $fp

array set tmp [t array_get tab]
if {"$tmp(name)" != "tab\there"} {
    error "quote-uri: got [list $tmp(name)] expected [list "tab\there"]"
}

array set tmp [t array_get newline]
if {"$tmp(name)" != "new\nline"} {
    error "quote-uri: got [list $tmp(name)] expected [list "new\nline"]"
}

puts "quoting test {-quote escape}"

set fp [open /tmp/escape_test.tsv w]
t search -quote escape -write_tabsep $fp -with_field_names 1
close $fp

t reset

set fp [open /tmp/escape_test.tsv r]
t read_tabsep $fp -quote escape -with_field_names
close $fp

array set tmp [t array_get tab]
if {"$tmp(name)" != "tab\there"} {
    error "quote-escape: got [list $tmp(name)] expected [list "tab\there"]"
}

array set tmp [t array_get newline]
if {"$tmp(name)" != "new\nline"} {
    error "quote-escape: got [list $tmp(name)] expected [list "new\nline"]"
}

puts "finished"


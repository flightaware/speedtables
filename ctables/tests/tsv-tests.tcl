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
   set fp [open tmp_top_brands.tsv w]
   eval [concat [list t search -write_tabsep $fp] $list]
   close $fp
   set fp [open tmp_top_brands.tsv r]
   if ![gets $fp line] {
      error "no data written to tmp_top_brands.tsv"
   }
   close $fp
   if {"$expected" != "" && "$line" != "$expected"} {
      regsub -all "\t" $line {\t} tline
      regsub -all "\t" $expected {\t} texpected
      error "bad data in tmp_top_brands.tsv\n\texpected $texpected\n\tgot $tline"
   }
}

check_first_line {} ""
check_first_line {-sort rank} "coke\t1\tCoca-Cola\t67394"
check_first_line {-sort name} "aol\t82\tAOL\t3248"
check_first_line {-with_field_names 1 -fields {name value}} "_key\tname\tvalue"

puts "read/write test"
t reset
set fp [open tmp_top_brands.tsv r]
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

set fp [open tmp_top_brands.tsv r]
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
set fp [open tmp_wonky_brands.tsv w]
t search -write_tabsep $fp -with_field_names 1 -fields {name rank value}
close $fp

t reset

set fp [open tmp_wonky_brands.tsv r]
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
set fp [open tmp_extra_brands.tsv w]
puts $fp "_key\tname\tcharm\trank\tserial\tvalue"
t search -key k -array_with_nulls a -code {
	puts $fp "$k\t$a(name)\t[expr {int(rand() * 10.0 + 1)}]\t$a(rank)\t[clock seconds]\t$a(value)"
}
close $fp
t reset

set fp [open tmp_extra_brands.tsv r]
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
t set newline name "new\r\nline" rank 66 value 66

set fp [open tmp_quote_test.tsv w]
t search -quote uri -write_tabsep $fp -with_field_names 1
close $fp

set fp [open tmp_quote_test.tsv r]
set count 0
while {[gets $fp line] >= 0} {
   if {"$line" == "newline\t66\tnew%0d%0aline\t66"} { incr count }
   if {"$line" == "tab\t66\ttab%09here\t66"} { incr count }
}
if {$count != 2} {
   error "Didn't find both URI-quoted lines in tmp_quote_test.tsv"
}
close $fp

t reset

set fp [open tmp_quote_test.tsv r]
t read_tabsep $fp -quote uri -with_field_names
close $fp

array set tmp [t array_get tab]
if {"$tmp(name)" != "tab\there"} {
    error "quote-uri: got [list $tmp(name)] expected [list "tab\there"]"
}

array set tmp [t array_get newline]
if {"$tmp(name)" != "new\r\nline"} {
    error "quote-uri: got [list $tmp(name)] expected [list "new\r\nline"]"
}

puts "quoting test {-quote escape}"

set fp [open tmp_escape_test.tsv w]
t search -quote escape -write_tabsep $fp -with_field_names 1
close $fp

set fp [open tmp_escape_test.tsv r]
set count 0
while {[gets $fp line] >= 0} {
   if {"$line" == "newline\t66\tnew\\r\\nline\t66"} { incr count }
   if {"$line" == "tab\t66\ttab\\there\t66"} { incr count }
}
if {$count != 2} {
   error "Didn't find both backslash-escaped lines in tmp_escape_test.tsv"
}
close $fp

t reset

set fp [open tmp_escape_test.tsv r]
t read_tabsep $fp -quote escape -with_field_names
close $fp

array set tmp [t array_get tab]
if {"$tmp(name)" != "tab\there"} {
    error "quote-escape: got [list $tmp(name)] expected [list "tab\there"]"
}

array set tmp [t array_get newline]
if {"$tmp(name)" != "new\r\nline"} {
    error "quote-escape: got [list $tmp(name)] expected [list "new\r\nline"]"
}

puts "polling"
set count 0
t reset
set fp [open top-brands.tsv r]
t read_tabsep $fp -poll_interval 2 -poll_code "incr count"
close $fp
if {$count != 50} {
    error "polling: got count=$count expected 50"
}

puts "polling foreground"
set count 0
t reset
set fp [open top-brands.tsv r]
t read_tabsep $fp -foreground -poll_interval 2 -poll_code {
	incr count
	if {$count == 2} break
}
close $fp
if {$count != 2} {
    error "polling: got count=$count expected 2"
}

puts "finished"


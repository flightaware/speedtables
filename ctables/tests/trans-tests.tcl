#
# check "search -delete" and "search -update"
#
# $Id$
#

source test_common.tcl

source top-brands-nokey-def.tcl

set id 1
foreach word {abacinate abacination abaciscus abacist aback abactinal
abactinally abaction abactor abaculus abacus Abadite abaff abaft abaisance
abaiser abaissed abalienate abalienation abalone} {
  t store id $id rank [string length $word] name $word
}

set names [t names]
t search -key k -compare {{= name abactor}} -code {set key $k}
t search -compare {{= name abactor}} -delete 1
if {[t count] != 19} {
  error "search -delete failed, expecting 19 times got [t count]"
}
regsub -all " $key " $names { } names
if {"[t names]" != "$names"} {
  error "search -delete failed, expecting $names got [t names]"
}
t search -compare {{= rank 5}} -delete 1
if {[t count] != 16} {
  error "search -delete failed, expecting 19 times got [t count]"
}

t search -compare {{= rank 6}} -update {name XXXXXX}
t search -compare {{= name Abadite}} -update {name Xxxxxxx}
t search -array a -code {
  lappend list([string match "X*" $a(name)]) $a(name)
}
if {"[lsort $list(1)]" != "XXXXXX Xxxxxxx"} {
  error "search -update failed, expecting {XXXXXX Xxxxxxx} got {[lsort $list(1)]}"
}

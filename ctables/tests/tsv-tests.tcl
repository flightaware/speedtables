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

suck_in_top_brands

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}

suck_in_top_brands

if {[t count] != 100} {
    error "expected count of 100 but got [t count]"
}


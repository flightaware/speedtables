#
# program to generate reasonably credible MAC and IP addresses
#
# $Id$
#

proc random_byte {} {
    return [expr {int(rand() * 256)}]
}

proc gen_ip {} {
    return [format "%d.%d.%d.%d" [random_byte] [random_byte] [random_byte] [random_byte]]
}

proc gen_mac {} {
    return [format "00:%02x:%02x:%02x:%02x:%02x" [random_byte] [random_byte] [random_byte] [random_byte] [random_byte]]
}

#
# doit - generate the data
#
# by forcing srand to a fixed integer, we should always generate the same
# data, hence we can expect this data to be standard
#
# to make sure, we check the last name generated -- if it doesn't match what
# we expect, they did not get good test data where by good we mean data that
# will match the results expected by the test software.
#
proc main {} {
    expr {srand(71077345)}

    set fp [open ../test-data.txt]
    while {[gets $fp line] >= 0} {
        puts "[lindex [split $line "\t"] 0]\t[gen_mac]\t[gen_ip]"
    }


    exit 0
}

if !$tcl_interactive main

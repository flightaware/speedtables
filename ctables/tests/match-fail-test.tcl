#
# check that search match against non-string field errors out
#
# $Id$
#

source test_common.tcl

package require ctable

source searchtest-def.tcl

source dumb-data.tcl

puts -nonewline stderr "Checking search -compare match fail for invalid type ... "
set expected {term "age" must be a string type for match operation while processing search compare}

if ![catch {t search -compare {{match age 3*}}} errmsg] {
	error "Match failed to fail"
}

if {"$errmsg" != "$expected"} {
	error "Expecting '$expected'\nGot '$errmsg'\nMatch fail in unexpected way"
}

puts stderr "OK"

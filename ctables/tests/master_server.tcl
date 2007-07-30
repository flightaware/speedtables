#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_server

set suffix _m

source top-brands-nokey-def.tcl


top_brands_nokey_m create m master file sharefile.dat

proc suck_in_top_brands_nokeys {} {
    set fp [open top-brands.tsv]
    set lastKey [m read_tabsep $fp -nokeys]
    close $fp
    if {"$lastKey" == ""} {
	error "should have returned next key value"
    }
    return $lastKey
}

m index create id
m index create rank
m index create name
m index create value

suck_in_top_brands_nokeys

puts "Contents"
m search -key k -array_get a -code {puts "$k : $a"}

::ctable_server::register ctable://*:1616/master m

puts "running, waiting for connections"

if !$tcl_interactive { vwait die }


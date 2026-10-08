#
# $Id$
#

package require ctable_server

namespace eval ::ctable_test {
    set suffix _m
}

source top-brands-nokey-def.tcl

top_brands_nokey_m create m master file sharefile.dat


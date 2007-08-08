#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_client

set suffix _m
set verbose 0

source top-brands-nokey-def.tcl

remote_ctable ctable://localhost:1616/master m

m shutdown


#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_client

set suffix _m

source top-brands-nokey-def.tcl

::ctable_client::remote_ctable ctable://localhost:1616/master m

set params [m attach [pid]]

top_brands_nokey_m create r reader $params


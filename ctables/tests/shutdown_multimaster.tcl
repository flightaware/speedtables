#
# make sure the auto row ID thing is working when read_tabsepping with nokeys
#
# $Id$
#

package require ctable_client

remote_ctable ctable://localhost:1616/elements elements

elements shutdown


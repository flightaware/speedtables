#
# very simple client/server tests
#
# this connects to the server that's serving the dumb data
#
# $Id$
#

package require ctable_client

remote_ctable ctable://127.0.0.1/dumbData t

# use to test redirect
#remote_ctable ctable://127.0.0.1:11112/dumbData t


#
# demo server with a redirect
#
# this tests the redirect capability by setting up a ctable server on port
# 11112 and redirecting requests for testTable to a ctable server on port
# 11111.
#
# $Id$
#

source dumb-data.tcl

package require ctable_server

::ctable_server::register_redirect ctable://*:11112/dumbData ctable://127.0.0.1/dumbData

vwait die

if !$tcl_interactive doit


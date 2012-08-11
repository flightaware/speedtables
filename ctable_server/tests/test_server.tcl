# $Id$

lappend auto_path stobj
package require C_test
package require ctable_server

set ::ctable_server::logfile stderr

set ctable [c_test create #auto]

::ctable_server::register sttp://*:1984/test $ctable

::ctable_server::serverwait

puts stderr "[pid] Normal exit"

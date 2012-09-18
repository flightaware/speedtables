# $Id$

package require ctable_client

remote_ctable sttp://localhost:1984/test c_test

set status 0

if [catch {
    set old_info [c_test info]
    puts "Got version '$old_info'"
    puts "Restarting server"
    if [catch {exec sh -c ./restart_server.sh >@stdout 2>@stderr} err] {
	error $err
    }
    puts "Trying again"
    set new_info [c_test info]
    puts "Got version '$new_info'"

    if {"$old_info" != "$new_info"} {
	error "Mismatch, expected '$old_info' got '$new_info'"
    }
} err] {
   puts "Test failed - $err"
   set status 1
}

exit $status

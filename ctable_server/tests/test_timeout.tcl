# $Id$

package require ctable_client

set URL sttp://localhost:1984/test
remote_ctable $URL c_test -timeout 500

set status 0

if [catch {

    set found_methods [c_test methods]
    if ![info exists ctableTimeout($URL)] {
	error "No timeout set for $URL"
    }
    if ![info exists ctableSockets($URL)] {
	error "Can't find ctableSockets($URL)"
    }
    after 1000
    update
    if [info exists ctableSockets($URL)] {
	error "Didn't close ctableSockets($URL)"
    }
    set found_methods [c_test methods]
    if ![info exists ctableSockets($URL)] {
	error "Can't find ctableSockets($URL)"
    }
} err] {
   puts "Test failed - $err"
   set status 1
}

c_test shutdown

exit $status

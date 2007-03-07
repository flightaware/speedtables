# $Id$

package require ctable_client

remote_ctable ctable://localhost:1984/test c_test

set status 0

if [catch {
    puts "version=[c_test info]"

    puts "sequence=[c_test sequenced]"

    c_test set * name pizza value pepperoni
    c_test set * name tea value "earl grey, hot"

    puts "sequence=[c_test sequenced]"

    c_test search -key k -array_get a -code {
	puts "$k: $a"
    }
} err] {
   puts "Test failed - $err"
   set status 1
}

c_test shutdown

exit $status

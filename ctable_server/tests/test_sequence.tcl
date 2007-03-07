# $Id$

package require ctable_client

remote_ctable ctable://localhost:1984/test c_test

set status 0

if [catch {
    puts "version=[c_test info]"

    # Set sequence on key
    c_test sequence

    puts "sequence=[c_test sequenced]"

    c_test set * name pizza value pepperoni
    c_test set * name tea value "earl grey, hot"

    puts "sequence=[c_test sequenced]"

    c_test search -key k -array_get _a -code {
	puts "$k: $_a"
    }

    c_test sequence id 100

    puts "sequence=[c_test sequenced]"

    c_test search -key k -array a -code {
	set key($a(name)) $k
    }

    foreach {name id} [array get key] {
	c_test set $id id $id
    }
    
    puts "sequence=[c_test sequenced]"

    c_test set -1 name fish value trout
    c_test set -2 name fish value mutton

    puts "sequence=[c_test sequenced]"

    c_test set $key(pizza) value hawaiian

    puts "sequence=[c_test sequenced]"

    c_test set -3 name fish value surreal id -3

    puts "sequence=[c_test sequenced]"

    c_test search -key k -array_get _a -code {
	puts "$k: $_a"
    }

} err] {
   puts "Test failed - $err"
   set status 1
}

c_test shutdown

exit $status

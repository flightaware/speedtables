# $Id$

package require ctable_client

remote_ctable sttp://localhost:1984/test c_test

set status 0

if [catch {
    puts "version=[c_test info]"

    set expected_methods {get set store incr array_get array_get_with_nulls exists delete count batch search search+ type import_postgres_result fields field fieldtype needs_quoting names reset destroy statistics read_tabsep write_tabsep index foreach methods shutdown redirect quit info create tablemakers tables help methods enable eval trigger key makekey attach getprop share}

    set required_methods $expected_methods
    set found_methods [c_test methods]

    foreach method $found_methods {
	if {[lsearch $expected_methods $method] == -1} {
	    error "Unexpected method $method"
	}
    }
    puts "no unexpected methods found"

    foreach method $required_methods {
	if {[lsearch $found_methods $method] == -1} {
	    error "Missing method $method"
	}
    }
    puts "all required methods found"

} err] {
   puts "Test failed - $err"
   set status 1
}

c_test shutdown

exit $status

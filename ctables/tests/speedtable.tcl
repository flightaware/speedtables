#
# Make sure the speedtable interface works
#

source test_common.tcl

set ::ctable::showCompilerCommands 1
set ::ctable::errorDebug 1


speedtables Topbrands 1.0 {

table top_brands {
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

puts "BEGIN DEBUG OUTPUT"
if {[catch {puts [exec du -a .]} err]} {
	puts "du error: $err"
}
puts "END DEBUG OUTPUT"

package require Topbrands

top_brands create t

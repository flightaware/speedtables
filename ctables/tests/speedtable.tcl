#
# Make sure the speedtable interface works
#

source test_common.tcl

speedtables Topbrands 1.0 {

table top_brands {
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrands

top_brands create t

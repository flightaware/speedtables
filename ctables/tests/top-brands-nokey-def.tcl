#
# test top brands definition
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

namespace eval ::ctable_test {
    if {![info exists suffix]} {
	set suffix ""
    }
}

CExtension topbrandsnokey$::ctable_test::suffix 1.0 {

CTable top_brands_nokey$::ctable_test::suffix {
    varstring id indexed 1
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrandsnokey$::ctable_test::suffix

top_brands_nokey$::ctable_test::suffix create t

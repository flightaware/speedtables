#
# test top brands definition
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

if {![info exists suffix]} {
    set suffix ""
}

CExtension topbrandsnokey$suffix 1.0 {

CTable top_brands_nokey$suffix {
    varstring id indexed 1
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrandsnokey$suffix

top_brands_nokey$suffix create t

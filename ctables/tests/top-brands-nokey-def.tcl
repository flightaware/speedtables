#
# test top brands definition
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension topbrandsnokey 1.0 {

CTable top_brands_nokey {
    varstring id indexed 1
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrandsnokey

top_brands_nokey create t

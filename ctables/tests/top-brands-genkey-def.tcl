#
# test top brands definition
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension topbrandsgenkey 1.0 {

CTable top_brands_genkey {
    key id
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrandsgenkey

top_brands_genkey create t

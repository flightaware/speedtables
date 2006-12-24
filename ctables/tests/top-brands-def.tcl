#
# test top brands definition
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension topbrands 1.0 {

CTable top_brands {
    int rank indexed 1
    varstring name indexed 1
    int value indexed 1
}

}

package require Topbrands

top_brands create t

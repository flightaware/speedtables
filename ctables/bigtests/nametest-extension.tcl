#
# test ctables search routine
#
# $Id$
#

package require ctable

CExtension nametest 1.0 {

CTable nameTable {
    varstring name indexed 1
    float latitude
    float longitude indexed 1
}

}

package require Nametest

nameTable create n


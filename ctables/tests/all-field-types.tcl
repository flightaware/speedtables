#
# test ctables search routine
#
# $Id$
#

source test_common.tcl

package require ctable

CExtension all_field_types 1.0 {

CTable allFieldTypes {
    boolean booleanvar
    fixedstring fixedstringvar 10
    varstring varstringvar
    char charvar
    mac macvar
    short shortvar
    int intvar
    long longvar
    wide widevar
    float floatvar
    double doublevar
    inet inetvar
    tclobj tclobjvar
}

}


#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension all_field_types_notnull 1.0 {

CTable allFieldTypesNotNull {
    boolean booleanvar notnull 1
    fixedstring fixedstringvar 10 notnull 1
    varstring varstringvar notnull 1
    char charvar notnull 1
    mac macvar notnull 1
    short shortvar notnull 1
    int intvar notnull 1
    long longvar notnull 1
    wide widevar notnull 1
    float floatvar notnull 1
    double doublevar notnull 1
    inet inetvar notnull 1
    tclobj tclobjvar notnull 1
}

}


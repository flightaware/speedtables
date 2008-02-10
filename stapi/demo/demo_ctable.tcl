# $Id$

CTableBuildPath /usr/local/lib/rivet/packages-local/sttp_demo/ctables

CExtension demo_ctable 1.0 {

CTable c_demo_ctable {
    key		isbn
    varstring	title
    varstring	author
}

}

lappend auto_path /usr/local/lib/rivet/packages-local/sttp_demo/ctables

package require Demo_ctable

package provide demo_ctable 1.0

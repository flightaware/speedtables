# $Id$

package require stapi_demo_config

CExtension demo_ctable 1.0 {

CTable c_demo_ctable {
    key		isbn
    varstring	title
    varstring	author
}

}

package require Demo_ctable

package provide demo_ctable 1.0

# $Id$
namespace eval ::ctable set srcDir $dir
package ifneeded ctable 1.1 [list source [file join $dir gentable.tcl]]

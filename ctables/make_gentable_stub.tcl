# $Id$

# Generate a gentable stub using the correct ctable package version

source gentable.tcl
puts "# generated [clock format [clock seconds]]

# Stub, to allow 'package require speedtable' to work during the transition.

package require ctable $::ctable::ctablePackageVersion
package provide speedtable $::ctable::ctablePackageVersion"


#!/bin/sh

# $Id$

# Create sysconfig.tcl from tclConfig.sh

versions="8.4"
prefixes="/usr/fa/lib/tcl /usr/local/lib/tcl /usr/lib/tcl /System/Library/Frameworks/Tcl.framework/Versions/ $*"

for version in $versions
do
  for prefix in $prefixes
  do
    try="$prefix$version/tclConfig.sh"
    if [ -f "$try" ]
    then
      config="$try"
      break 2
    fi
  done
done

if [ -z "$config" ]
then
  echo "No tclConfig.sh file"
  exit 2
fi

set -e

. $config

echo "# Generated from $config `date`"
echo "set sysconfig(cc) {$TCL_CC}"
echo "set sysconfig(ccflags) {$TCL_DEFS $TCL_EXTRA_CFLAGS $TCL_INCLUDE_SPEC}"
echo "set sysconfig(warn) {$TCL_CFLAGS_WARNING}"
echo "set sysconfig(ldflags) {$TCL_SHLIB_CFLAGS}"
echo "set sysconfig(ld) {`eval echo $TCL_SHLIB_LD`}"
echo "set sysconfig(shlib) {$TCL_SHLIB_SUFFIX}"
echo "set sysconfig(dbgx) {$TCL_DBGX}"
echo "set sysconfig(libg) {`eval echo $TCL_LIB_SPEC`}"
echo "set sysconfig(dbg) {$TCL_CFLAGS_DEBUG}"
echo "set sysconfig(opt) {$TCL_CFLAGS_OPTIMIZE}"
if [ "$TCL_SUPPORTS_STUBS" = "1" ]
then
  echo "set sysconfig(stubg) {`eval echo $TCL_STUB_LIB_SPEC`}"
fi

# Generate again with no "g" flag, if necessary
TCL_DBGX=
echo "set sysconfig(lib) {`eval echo $TCL_LIB_SPEC`}"
if [ "$TCL_SUPPORTS_STUBS" = "1" ]
then
  echo "set sysconfig(stub) {`eval echo $TCL_STUB_LIB_SPEC`}"
fi

echo "# End of generated code"


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
echo "set sysconfig(ld) {$TCL_SHLIB_LD}"
echo "set sysconfig(shlib) {$TCL_SHLIB_SUFFIX}"
echo "set sysconfig(dbgx) {$TCL_DBGX}"
TCL_LIB="`eval echo $TCL_LIB_SPEC`"
echo "set sysconfig(libg) {$TCL_LIB}"
echo "set sysconfig(dbg) {$TCL_CFLAGS_DEBUG}"
echo "set sysconfig(opt) {$TCL_CFLAGS_OPTIMIZE}"
if [ "$TCL_SUPPORTS_STUBS" = "1" ]
then
  TCL_STUB_LIB="`eval echo $TCL_STUB_LIB_SPEC`"
  echo "set sysconfig(stubg) {$TCL_STUB_LIB}"
fi
TCL_DBGX=
TCL_LIB="`eval echo $TCL_LIB_SPEC`"
echo "set sysconfig(lib) {$TCL_LIB}"
if [ "$TCL_SUPPORTS_STUBS" = "1" ]
then
  TCL_STUB_LIB="`eval echo $TCL_STUB_LIB_SPEC`"
  echo "set sysconfig(stub) {$TCL_STUB_LIB}"
fi

echo "# End of generated code"


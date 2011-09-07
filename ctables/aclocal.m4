#
# Include the TEA standard macro set
#

builtin(include,../tclconfig/tcl.m4)

#
# Add here whatever m4 macros you want to define for your package
#



# 
# Create sysconfig.tcl from tclConfig.sh and other things
#
AC_DEFUN([CTABLES_MAKE_SYSCONFIG_TCL], [

AC_REQUIRE([TEA_PATH_TCLCONFIG])
AC_REQUIRE([TEA_LOAD_TCLCONFIG])

# Start by deleting any previous sysconfig.tcl
rm -f sysconfig.tcl

# Round-about way to get the ld command, which may reference "$@" on some platforms.
ctable_get_shlib_ld ()
{
    eval echo $TCL_SHLIB_LD
}
sysconfig_ld=`ctable_get_shlib_ld dummy`


sysconfig_tcl_content="set sysconfig(ctablePackageVersion) {$PACKAGE_VERSION}
set sysconfig(cc) {$TCL_CC}
set sysconfig(ccflags) {$TCL_DEFS $TCL_EXTRA_CFLAGS $TCL_INCLUDE_SPEC $CTABLES_CFLAGS}
set sysconfig(warn) {$TCL_CFLAGS_WARNING}
set sysconfig(ldflags) {$TCL_SHLIB_CFLAGS}
#set sysconfig(ld) {`eval echo $TCL_SHLIB_LD`}
set sysconfig(ld) {$sysconfig_ld}
set sysconfig(shlib) {$TCL_SHLIB_SUFFIX}
set sysconfig(dbgx) {$TCL_DBGX}
set sysconfig(libg) {`eval echo $TCL_LIB_SPEC`}
set sysconfig(dbg) {$TCL_CFLAGS_DEBUG}
set sysconfig(opt) {$TCL_CFLAGS_OPTIMIZE}"

if test "$TCL_SUPPORTS_STUBS" -eq 1; then
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(stubg) {`eval echo $TCL_STUB_LIB_SPEC`}"
fi

# Generate again with no "g" flag, if necessary
TCL_DBGX=
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(lib) {`eval echo $TCL_LIB_SPEC`}"
if test "$TCL_SUPPORTS_STUBS" -eq 1 ; then
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(stub) {`eval echo $TCL_STUB_LIB_SPEC`}"
fi




# Handle the --with-pgsql configure option.
AC_ARG_WITH([pgsql],
	[  --with-pgsql[=PATH]       Build with pgsql/pgtcl library support],
[
AC_MSG_CHECKING([location of pgsql and pgtcl])
if test "x$withval" = "x" -o "$withval" = "yes"; then
  pg_prefixes="/usr/local /usr/local/pgsql /usr"
else
  pg_prefixes=$withval
fi

# Look for pgsql and pgtcl
for prefix in $pg_prefixes
do
  # look for pgsql frontend header
  if test -f $prefix/include/libpq-fe.h; then
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(pqprefix) $prefix"
  else
    continue
  fi

  # there may be multiple installed versions of pgtcl so sort with the highest version first.
  pg_libdirs=`find $prefix/lib -maxdepth 1 -name "pgtcl*.*" -type d | sort -rn`
  if test -z "$pg_libdirs"; then
     continue
  fi

  # look for pgtcl-ng before pgtcl
  pgtclver=""
  for dir in $pg_libdirs
  do
    if test -f $dir/pkgIndex.tcl; then
      pgtclver=`basename /usr/local/lib/pgtcl1.8 | sed s/^pgtcl//`
      sysconfig_tcl_content="$sysconfig_tcl_content
      set sysconfig(pgtclver) $pgtclver
      set sysconfig(pgtclprefix) $prefix"
      break
    fi
  done

  # look for pgtcl
  if test -z "$pgtclver"; then
    for dir in $pg_libdirs
    do
      if test -f $dir/pgtcl.tcl; then
        pgtclver=`basename /usr/local/lib/pgtcl1.8 | sed s/^pgtcl//`
        sysconfig_tcl_content="$sysconfig_tcl_content
        set sysconfig(pgtclver) $pgtclver
        set sysconfig(pgtclprefix) $prefix"
	break
      fi
    done
  fi

  pg_prefixes=$dir
  break
done

if test -z "$pgtclver"; then
  AC_MSG_ERROR([pgsql and/or pgtcl not found under $pg_prefixes])
fi

AC_MSG_RESULT([found under $pg_prefixes])

])




AC_CONFIG_COMMANDS([sysconfig.tcl], [], [cat << _STEOF > sysconfig.tcl
# Generated on `date`
$sysconfig_tcl_content
# End of generated code
_STEOF
])

])


#
# Include the TEA standard macro set
#

builtin(include,../tclconfig/tcl.m4)

#
# Add here whatever m4 macros you want to define for your package
#

builtin(include,boost.m4)

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
set sysconfig(cxx) {$CXX}
set sysconfig(cxxld) {$CXX -shared}
set sysconfig(ccflags) {$TCL_DEFS $TCL_EXTRA_CFLAGS $TCL_INCLUDE_SPEC $CTABLES_CFLAGS $BOOST_CPPFLAGS}
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
AC_ARG_WITH([pgsql-include],
	[  --with-pgsql-include[=PATH]       Build with pgsql/pgtcl library support],
[
AC_MSG_CHECKING([location of libpq include file])
if test "x$withval" = "x" -o "$withval" = "yes"; then
  pg_prefixes="/usr/local/include /usr/local/pgsql/include /usr/include /usr/include/postgresql"
else
  pg_prefixes=$withval
fi

# Look for pgsql and pgtcl
for prefix in $pg_prefixes
do
  # look for pgsql frontend header
  if test -f $prefix/libpq-fe.h; then
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(pqprefix) $prefix"
pqprefix=$prefix
  else
    continue
  fi
done
if test -z "$pqprefix"; then
  AC_MSG_ERROR([pgsql libpq-fe.h include file not found under $pg_prefixes])
fi

AC_MSG_RESULT([found under $pqprefix])
])

AC_ARG_WITH([pgtcl-lib],
	[  --with-pgtcl-lib[=PATH]       Build with pgsql/pgtcl library support],
[
AC_MSG_CHECKING([location of pgtcl])
if test "x$withval" = "x" -o "$withval" = "yes"; then
  pg_prefixes="/usr/lib /usr/local/lib"
else
  pg_prefixes=$withval
fi

# Look for pgsql and pgtcl
for prefix in $pg_prefixes
do
  # there may be multiple installed versions of pgtcl so sort with the highest version first.
  pg_libdirs=`find $prefix -maxdepth 2 -name "pgtcl*" -type d | sort -rn`

  if test -z "$pg_libdirs"; then
     continue
  fi

  pgtclver=""
  for dir in $pg_libdirs
  do
    if test -f $dir/pkgIndex.tcl; then
      #pgtclver=`basename $dir | sed s/^pgtcl//`
      pgtclver=`grep "package ifneeded Pgtcl" $dir/pkgIndex.tcl| cut -d' ' -f4`
      sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(pgtclver) $pgtclver
set sysconfig(pgtclprefix) $dir"
      break
    fi
  done

  # look for pgtcl
  if test -z "$pgtclver"; then
    for dir in $pg_libdirs
    do
      if test -f $dir/pgtcl.tcl; then
        pgtclver=`basename $dir | sed s/^pgtcl//`
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

# Handle the --with-casstcl configure option.
AC_ARG_WITH([casstcl],
	[  --with-casstcl[=PATH]       Build with cassandra/casstcl library support],
[
AC_MSG_CHECKING([location of cassandra and casstcl])
if test "x$withval" = "x" -o "$withval" = "yes"; then
  cass_prefixes="/usr/local /usr/local/cassandra /usr"
else
  cass_prefixes=$withval
fi

# Look for cassandra and casstcl
for prefix in $cass_prefixes
do
  # look for cassandra include file
  if test -f $prefix/include/cassandra.h; then
sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(cassprefix) $prefix"
  else
    continue
  fi

  # there may be multiple installed versions of casstcl so sort with the highest version first.
  cass_libdirs=`find $prefix/lib -maxdepth 1 -name "casstcl*" -type d | sort -rn`

  if test -z "$cass_libdirs"; then
     continue
  fi

  # look for casstcl
  if test -z "$casstclver"; then
    for dir in $cass_libdirs
    do
      if test -f $dir/casstcl.tcl; then
        casstclver=`basename $dir | sed s/^casstcl//`
        sysconfig_tcl_content="$sysconfig_tcl_content
set sysconfig(casstclver) $casstclver
set sysconfig(casstclprefix) $dir"
	break
      fi
    done
  fi

  cass_prefixes=$dir
  break
done

if test -z "$casstclver"; then
  AC_MSG_ERROR([cassandra and/or casstcl not found under $cass_prefixes])
fi

AC_MSG_RESULT([found under $cass_prefixes])

])


AC_CONFIG_COMMANDS([sysconfig.tcl], [], [cat << _STEOF > sysconfig.tcl
# Generated on `date`
$sysconfig_tcl_content
# End of generated code
_STEOF
])

])


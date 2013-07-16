#
# Include the TEA standard macro set
#

builtin(include,tclconfig/tcl.m4)

#
# Add here whatever m4 macros you want to define for your package
#

builtin(include,ctables/boost.m4)


# Handle the --with-pgsql configure option.
AC_ARG_WITH([pgsql],
	[  --with-pgsql[=PATH]       Build with pgsql/pgtcl library support],
[
with_pgsql=$withval
])


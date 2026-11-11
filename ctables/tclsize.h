/*
 * Tcl_Size was introduced in Tcl 9.  speedables still supports building against
 * Tcl 8.6, where Tcl object and list sizes are int-sized.
 */
#ifndef TCL_SIZE_MAX
# define Tcl_GetSizeIntFromObj Tcl_GetIntFromObj
# define TCL_SIZE_MAX      INT_MAX
# ifndef Tcl_Size
    typedef int Tcl_Size;
# endif
# define TCL_SIZE_MODIFIER ""
#endif

## Speedtables

Speed tables is a high-performance memory-resident database. The speed
table compiler reads a table definition and generates a set of C
access routines to create, manipulate and search tables containing
millions of rows. Currently oriented towards Tcl.  Licensed under BSD Copyright.

## Useful Links

* [Source Code](http://github.com/flightaware/speedtables)
* [Project Page](http://flightaware.github.io/speedtables)

For more details about Speed tables, see ctables/docs/doc.txt

This repository consists of three separate Tcl packages:

* ctables -- the primary package providing single-process and shared-memory tables.
* ctable_server -- networked client and server interface using "sttp:" URI syntax.
* stapi -- abstraction to allow ctables, ctable_server, and other interchangable object use.

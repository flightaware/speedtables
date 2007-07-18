C=shared.c
T=testmaster
X=$C $T.c
O=${C:.c=.o}
S=shared.so

U=/usr/local

STUB=$U/lib/libtclstub84g.a

SFLAGS=-shared -fPIC -I$U/include -I$U/include/tcl8.4 -fno-common -DUSE_TCL_STUBS=1 

CFLAGS=-g -Wall -Wno-implicit-int

$T: $T.o $O
	${CC} ${CFLAGS} -o $T $T.o $O

$S: $C
	${CC} ${CFLAGS} ${SFLAGS} -DTCL_EXTENSION -o $S $C ${STUB}

clean:
	rm -f $O $T.o $S test.map

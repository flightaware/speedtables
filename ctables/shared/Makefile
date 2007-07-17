C=shared.c stubs.c
T=testmaster
X=$C $T.c
O=${C:.c=.o}

$T: $T.o $O
	${CC} ${CFLAGS} -o $T $T.o $O


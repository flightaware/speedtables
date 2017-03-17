CC=g++

all: dumper

clean:
	-rm dumper dumper.o shared.o

dumper: shared.o dumper.o
	$(CC) -o dumper dumper.o shared.o

.c.o:
	$(CC) -c $< -o $@

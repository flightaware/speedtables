CC=g++

all: st_dumper

clean:
	-rm st_dumper dumper.o shared.o

st_dumper: shared.o dumper.o
	$(CC) -o st_dumper dumper.o shared.o

.c.o:
	$(CC) -c $< -o $@

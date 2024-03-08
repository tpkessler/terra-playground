CFLAGS=-O2 -march=native

all: libexport.so libtinymt.so

libexport.so: export.o
	$(CC) -shared $^ -o $@

export.o: export.t export_decl.t
	terra export.t

libtinymt.so: tinymt32.o tinymt64.o
	$(CC) -shared $^ -o $@

tinymt32.o: tinymt/tinymt32.c
	$(CC) $(CFLAGS) $^ -c -o $@

tinymt64.o: tinymt/tinymt64.c
	$(CC) $(CFLAGS) $^ -c -o $@

test: libexport.so libtinymt.so
	terra import.t
	terra test_random.t

.PHONY: clean realclean

clean:
	$(RM) export.o tinymt32.o tinymt64.o

realclean: clean
	$(RM) libexport.so libtinymt.so


uname_s := $(shell uname -s)
ifeq ($(uname_s),Linux)
	dyn := so
else ifeq ($(uname_s),Darwin)
	dyn := dylib
else
	$(error Unsupported build environment!)
endif


CFLAGS=-O2 -march=native

all: libexport.$(dyn) libtinymt.$(dyn)

libexport.$(dyn): export.o
	$(CC) -fPIC -shared $^ -o $@

export.o: export.t export_decl.t
	terra export.t

libtinymt.$(dyn): tinymt32.o tinymt64.o
	$(CC) -fPIC -shared $^ -o $@

tinymt32.o: tinymt/tinymt32.c
	$(CC) $(CFLAGS) $^ -c -o $@

tinymt64.o: tinymt/tinymt64.c
	$(CC) $(CFLAGS) $^ -c -o $@

test: libexport.$(dyn) libtinymt.$(dyn)
	terra import.t
	terra test_random.t

.PHONY: clean realclean

clean:
	$(RM) export.o tinymt32.o tinymt64.o

realclean: clean
	$(RM) libexport.$(dyn) libtinymt.$(dyn)


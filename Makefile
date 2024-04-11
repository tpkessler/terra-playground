uname_s := $(shell uname -s)
ifeq ($(uname_s),Linux)
	dyn := so
else ifeq ($(uname_s),Darwin)
	dyn := dylib
else
	$(error Unsupported build environment!)
endif


CFLAGS=-O2 -march=native -fPIC

all: libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn)

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

FILE=  pcg-advance-8.c pcg-advance-16.c pcg-advance-32.c pcg-advance-64.c \
       pcg-advance-128.c pcg-output-8.c pcg-output-16.c pcg-output-32.c   \
       pcg-output-64.c pcg-output-128.c pcg-rngs-8.c pcg-rngs-16.c        \
       pcg-rngs-32.c pcg-rngs-64.c pcg-rngs-128.c \
       pcg-global-32.c pcg-global-64.c

SRC=$(patsubst %.c, pcg/%.c, $(FILE))
OBJ=$(patsubst %.c, %.o, $(FILE))

libpcg.$(dyn): $(OBJ)
	$(CC) -fPIC -shared $^ -o $@

$(OBJ): %.o: pcg/%.c
	$(CC) $(CFLAGS) $^ -c -o $@

test: libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn)
	terra import.t
	terra test_random.t

.PHONY: clean realclean

clean:
	$(RM) export.o tinymt32.o tinymt64.o $(OBJ)

realclean: clean
	$(RM) libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn)


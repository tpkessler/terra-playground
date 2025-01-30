# SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
# SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
#
# SPDX-License-Identifier: CC0-1.0

uname_s := $(shell uname -s)
ifeq ($(uname_s),Linux)
	dyn := so
else ifeq ($(uname_s),Darwin)
	dyn := dylib
else
	$(error Unsupported build environment!)
endif

TERRA?=terra
TERRAFLAGS?=-g

CFLAGS=-O2 -march=native -fPIC

all: libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn) libhash.$(dyn) libnonlinearbc.$(dyn)  gnuplot_i.$(dyn)


libnonlinearbc.$(dyn): nonlinearbc.o
	$(CC) -fPIC -shared $^ -o $@ -lpthread -lblas

libhash.$(dyn): hashmap.o
	$(CC) -fPIC -shared $^ -o $@

hashmap.o: hashmap/hashmap.c hashmap/hashmap.h
	$(CC) $(CFLAGS) $< -c -o $@

libexport.$(dyn): export.o
	$(CC) -fPIC -shared $^ -o $@

nonlinearbc.o: compile_boltzmann.t boltzmann.t
	$(TERRA) $(TERRAFLAGS) compile_boltzmann.t

export.o: export.t export_decl.t
	$(TERRA) $(TERRAFLAGS) export.t

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

gnuplot_i.$(dyn): gnuplot_i.o
	$(CC) -fPIC -shared $^ -o $@
	
gnuplot_i.o: gnuplot/src/gnuplot_i.c gnuplot/src/gnuplot_i.h
	$(CC) $(CFLAGS) -c -o gnuplot_i.o gnuplot/src/gnuplot_i.c

test: libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn)
	terra import.t
	terra test_random.t

.PHONY: clean realclean

clean:
	$(RM) export.o nonlinearbc.o tinymt32.o tinymt64.o $(OBJ)  gnuplot_i.o

realclean: clean
	$(RM) libexport.$(dyn) libtinymt.$(dyn) libpcg.$(dyn) libboltzmann.$(dyn) gnuplot_i.$(dyn)


all: libexport.so

libexport.so: export.o
	$(CC) -shared $< -o $@

export.o: export.t export_decl.t
	terra export.t

test: libexport.so
	terra import.t

.PHONY: clean realclean

clean:
	$(RM) export.o

realclean: clean
	$(RM) libexport.so


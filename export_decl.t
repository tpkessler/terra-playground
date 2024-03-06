terra addtwo :: {int, int} -> {int}

function matrix(T)
	return struct{
		a: &T
		rows: int64
		cols: int64
		ld: int64
	}
end

matrixDouble = matrix(double)
terra setone_double :: {&matrixDouble} -> {}
matrixFloat = matrix(float)
terra setone_float :: {&matrixFloat} -> {}

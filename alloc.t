local C = terralib.includecstring[[
	#include <stdio.h>
	#include <stdlib.h>
]]
local interface = require("interface")

local Allocator = interface.Interface:new{
	alloc = uint64 -> {&opaque},
	free = &opaque -> {}
}

local struct stdlib{
}

terra stdlib:alloc(size: uint64): &opaque
	var alignment = 64 -- Memory alignment for AVX512    
	var ptr: &opaque = nil 
	var res = C.posix_memalign(&ptr, alignment, size)

	if res ~= 0 then
		var size_gib = 1.0 * size / (1024 * 1024 * 1024)
		C.printf("Cannot allocate memory for buffer of size %g GiB\n",
							size_gib)
		C.abort()
	end

	return ptr
end

terra stdlib:free(ptr: &opaque)
	C.free(ptr)
end

Allocator:isimplemented(stdlib)


return {
		Default = stdlib,
		Allocator = Allocator,
	   }

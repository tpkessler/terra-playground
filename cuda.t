local cuda = {}
local alloc = require("alloc")
local err = require("assert")

local C = terralib.includec("cuda_runtime.h")

local instructions = {
	["threadIdx"] = "tid",
	["blockDim"] = "ntid",
	["blockIdx"] = "ctaid",
	["gridDim"] = "nctaid",
}

for cuname, instr in pairs(instructions) do
	cuda[cuname] = {}
	for _, s in ipairs({"x", "y", "z"}) do
		local name = "nvvm_read_ptx_sreg_" .. instr .. "_" .. s
		cuda[cuname][s] = cudalib[name]
	end
end

cuda.barrier0 = cudalib.nvvm_barrier0
-- https://reviews.llvm.org/D80464
cuda.__syncthreads = cuda.barrier0

cuda.DeviceSynchronize = C.cudaDeviceSynchronize
cuda.ThreadSynchronize = C.cudaThreadSynchronize
cuda.StreamSynchronize = terralib.externfunction("cuStreamSynchronize", {&opaque} -> int)

cuda.Malloc = C.cudaMalloc
cuda.MallocManaged = terra(data: &&opaque, size: uint64) return C.cudaMallocManaged(data, size, C.cudaMemAttachGlobal) end
cuda.Free = C.cudaFree
cuda.Success = C.cudaSuccess
cuda.Memcpy = C.cudaMemcpy
-- Wrapper for enum cudaMemcpyKind
local dev = {"Host", "Device"}
for _, src in pairs(dev) do
	for _, trg in pairs(dev) do
		local name = ("Memcpy%sTo%s"):format(src, trg)
		cuda[name] = C["cuda" .. name]
	end
end

local function castbuffer(arg)
	arg = terralib.newlist(arg)
	local typ = arg:map(function(a) return a:gettype() end)
	local Buffer = tuple(unpack(typ))
	return quote var buf = [Buffer] {[arg]} in [&int8](&buf) end
end
local vprintf = terralib.externfunction("cudart:vprintf", {&int8,&int8} -> int)
cuda.printf = macro(function(fmt, ...)
	local buf = castbuffer({...})
	return `vprintf(fmt, buf)
end)


cuda.DeviceAllocator = terralib.memoize(function(config)
	config = config or {}
	local is_managed = config["Managed"] == nil and true or config["Managed"]
	assert(type(is_managed) == "boolean")

	
	local cualloc = terralib.types.newstruct("cualloc")

	local size_t = alloc.size_t
	local block = alloc.block

	local cumalloc = macro(function(ptr, size)
		if is_managed then
			return quote var res = cuda.MallocManaged(&ptr, size) in err.assert(res == cuda.Success) end
		else
			return quote var res = cuda.Malloc(&ptr, size) in err.assert(res == cuda.Success) end
		end
	end)
	
	local Imp = {}
    terra Imp.__allocate :: {size_t, size_t} -> {block}
    terra Imp.__reallocate :: {&block, size_t, size_t} -> {}
    terra Imp.__deallocate :: {&block} -> {}
	local io = terralib.includec("stdio.h")
	
	terra Imp.__allocate(sz: size_t, num: size_t)
		var size = sz * num
		var ptr: &opaque = nil
		cumalloc(ptr, size)
		return block {ptr, size}
	end

	terra Imp.__deallocate(blk: &block)
		var ptr = blk.ptr
		var res = cuda.Free(ptr)
		err.assert(res == cuda.Success)
		blk:__init()
	end

	terra Imp.__reallocate(blk: &block, sz: size_t, num: size_t)
		var old_size = blk:size_in_bytes()
		var new_size = sz * num
		if blk:owns_resource() and old_size < new_size then
			var new_ptr: &opaque = nil
			cumalloc(new_ptr, new_size)
			var res = cuda.Memcpy(new_ptr, blk.ptr, old_size, cuda.MemcpyDeviceToDevice)
			err.assert(res == cuda.Success)
			blk:__dtor()
			blk.ptr = new_ptr
			blk.nbytes = new_size
		end
	end

	alloc.AllocatorBase(cualloc, Imp)
    alloc.Allocator:isimplemented(cualloc)

	return cualloc
end)


return cuda

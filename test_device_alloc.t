-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

if not terralib.cudalib then
    os.exit(0)
end
local cuda = require("cuda")
local dvector = require("dvector")
local io = terralib.includec("stdio.h")

local Alloc = cuda.DeviceAllocator{Managed = true}
local Vec = dvector.DynamicVector(double)

local terra kernel(x: Vec)
    var idx = cuda.threadIdx.x() + cuda.blockIdx.x() * cuda.blockDim.x()
    cuda.printf("idx = %d with entry %g\n", idx, x(idx))
    for xx in x do
        cuda.printf("Iterate over %g\n", xx)
    end
    if idx < x:size() then
        x(idx) = x:size() - idx
    end
end

if not __silent__ then --only run when silent mode is off

    kernel:printpretty()

    -- cudacompile initializes cuda runtime.
    -- TODO Is there a better way?
    local R = terralib.cudacompile{kernel = kernel}

    terra main()
        var alloc: Alloc
        var x = Vec.from(&alloc, 5, 7, 9)
        io.printf("Before:\n")
        for xx in x do
            io.printf("%g\n", xx)
        end
        io.printf("\n")
        var launch = terralib.CUDAParams {1, 1, 1,
                                        3, 1, 1,
                                        0, nil}
        R.kernel(&launch, x)
        -- Managed memory is only copied after a synchronization
        cuda.StreamSynchronize(nil)

        io.printf("After:\n")
        for xx in x do
            io.printf("%g\n", xx)
        end
    end
    main()

end

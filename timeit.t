local C = terralib.includec("stdio.h")
local timing = require("timing")

local timeit = macro(function(exp, verbose)
    local str = tostring(exp)
    if verbose == nil then
        verbose = tonumber(os.getenv("TERRA_VERBOSE")) or 0
        verbose = verbose > 0 and true or false
    end
    if verbose then
        local tree = exp.tree
        local filename = tree.filename
        local linenumber = tree.linenumber
        local offset = tree.offset
        local loc = filename .. ":" .. linenumber .. "+" .. offset
        return
            quote
                do
                    var sw: timing.parallel_timer
                    sw:start()

                    exp

                    var t = sw:stop()
                    C.printf(
                        [
                            loc .. ":" .. tostring(exp):gsub("\n", "")
                            .. " took %g ms\n"
                        ],
                        1e3 * t
                    )
                end
            end
    else
        return `exp
    end
end)

return {
    timeit = timeit,
}

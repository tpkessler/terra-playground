local math = require('mathfuns')
local alloc = require('alloc')
local dvector = require('dvector')

local size_t = uint32
local Allocator = alloc.Allocator
local vec = dvector.DynamicVector(double)

local legendre = terra(alloc : Allocator, n : size_t)
    if n==1 then
        return vec.from(&alloc, 0.0), vec.from(&alloc, 2.0)
    elseif n==2 then
        return vec.from(&alloc, -1.0 / math.sqrt(3.0), 1.0 / math.sqrt(3.0)), 
            vec.from(&alloc, 1.0, 1.0)
    elseif n==3 then
        return vec.from(&alloc, -math.sqrt(3.0 / 5.0), 0.0, math.sqrt(3.0 / 5.0)), 
            vec.from(&alloc, 5.0 / 9.0, 8.0 / 9.0, 5.0 / 9.0)
    elseif n==4 then
        var a = 2.0 / 7.0 * math.sqrt(6.0 / 5.0)
        return vec.from(&alloc, -math.sqrt(3. / 7. + a), -math.sqrt(3./7.-a), math.sqrt(3./7.-a), math.sqrt(3./7.+a)),
            vec.from(&alloc, (18. - math.sqrt(30.)) / 36., (18. + math.sqrt(30.)) / 36., (18. + math.sqrt(30.)) / 36., (18. - math.sqrt(30.)) / 36.)
    elseif n==5 then
        var b = 2.0 * math.sqrt(10.0 / 7.0)
        return vec.from(&alloc, -math.sqrt(5. + b) / 3., -math.sqrt(5. - b) / 3., 0.0, math.sqrt(5. - b) / 3., math.sqrt(5. + b) / 3.),
            vec.from(&alloc, (322. - 13. * math.sqrt(70.)) / 900., (322. + 13. * math.sqrt(70.)) / 900., 128. / 225., (322. + 13. * math.sqrt(70.)) / 900., (322. - 13. * math.sqrt(70.)) / 900.)
    elseif n <= 60 then
        -- Newton's method with three-term recurrence
        --return rec(n)
    else
        --use asymtotic expansions
        --return asy(n)
    end
end


local terra legpts_nodes(alloc : Allocator, n : size_t, a : vec)
    --ASYMPTOTIC EXPANSION FOR THE GAUSS-LEGENDRE NODES.
    var vn = 1. / (n + 0.5)
    var m = a:size()
    var nodes = a:map(alloc, math.cot)
    vn2 = vn * vn
    vn4 = vn2 * vn2

end 

--[[
    @inbounds if n ≤ 255
        vn⁶ = vn⁴ * vn²
        for i in 1:m
            u = nodes[i]
            u² = u^2
            ai = a[i]
            ai² = ai * ai
            ai³ = ai² * ai
            ai⁵ = ai² * ai³
            node = ai + (u - 1 / ai) / 8 * vn²
            v1 = (6 * (1 + u²) / ai + 25 / ai³ - u * muladd(31, u², 33)) / 384
            v2 = u * evalpoly(u², (2595 / 15360, 6350 / 15360, 3779 / 15360))
            v3 = (1 + u²) * (-muladd(31 / 1024, u², 11 / 1024) / ai +
                             u / 512 / ai² + -25 / 3072 / ai³)
            v4 = (v2 - 1073 / 5120 / ai⁵ + v3)
            node = muladd(v1, vn⁴, node)
            node = muladd(v4, vn⁶, node)
            nodes[i] = node
        end
    elseif n ≤ 3950
        for i in 1:m
            u = nodes[i]
            u² = u^2
            ai = a[i]
            ai² = ai * ai
            ai³ = ai² * ai
            node = ai + (u - 1 / ai) / 8 * vn²
            v1 = (6 * (1 + u²) / ai + 25 / ai³ - u * muladd(31, u², 33)) / 384
            node = muladd(v1, vn⁴, node)
            nodes[i] = node
        end
    else
        for i in 1:m
            u = nodes[i]
            ai = a[i]
            node = ai + (u - 1 / ai) / 8 * vn²
            nodes[i] = node
        end
    end
    @inbounds for jj = 1:m
        nodes[jj] = cos(nodes[jj])
    end

    return nodes
end



--]]








return {
    legendre = legendre
}


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
    --asymptotic expansion for the Gauss-Legendre nodes
    var vn = 1. / (n + 0.5)
    var m = a:size()
    var nodes = a:map(alloc, math.cot)
    var vn2 = vn * vn
    var vn4 = vn2 * vn2
    if n <= 255 then
        var vn6 = vn4 * vn2
        for i = 1, m do
            var u = nodes(i)
            var u2 = u * u
            var ai = a:get(i)
            var ai2 = ai * ai
            var ai3 = ai2 * ai
            var ai5 = ai2 * ai3
            var node = ai + (u - 1. / ai) / 8. * vn2
            var v1 = (6. * (1. + u2) / ai + 25. / ai3 - u * math.fusedmuladd(31., u2, 33.)) / 384.
            var v2 = u * math.evalpoly(u2, 2595. / 15360., 6350. / 15360., 3779. / 15360.)
            var v3 = (1. + u2) * (-math.fusedmuladd(31. / 1024., u2, 11. / 1024.) / ai + u / 512. / ai2 + -25. / 3072. / ai3)
            var v4 = (v2 - 1073. / 5120. / ai5 + v3)
            node = math.fusedmuladd(v1, vn4, node)
            node = math.fusedmuladd(v4, vn6, node)
            nodes(i) = node
        end
    end
    for jj=0,m do
        nodes(jj) = math.cos(nodes(jj))
    end
    return nodes
end

return {
    legendre = legendre
}


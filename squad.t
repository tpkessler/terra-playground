import "terraform"

local base = require("base")
local alloc = require('alloc')
local tmath = require('mathfuns')
local geo = require("geometry")
local vec = require("luavector")
local gauss = require("gauss")
local range = require("range")

local DefaultAllocator =  alloc.DefaultAllocator()

local Allocator = alloc.Allocator
local size_t = uint64
local T = double

--return a terra tuple type of length N: {T, T, ..., T}
local ntuple = function(T, N)
    local t = terralib.newlist()
    for i = 1, N do
        t:insert(T)
    end
    return tuple(unpack(t))
end

local Interval = terralib.memoize(function(T)

    local struct interval{
        _0 : T
        _1 : T
    }
    interval:setconvertible("tuple")

    function interval.metamethods.__typename(self)
        return ("interval(%s)"):format(tostring(T))
    end
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(interval)

    --entry lookup quadrature points and weights
    interval.metamethods.__entrymissing = macro(function(entryname, self)
        if entryname=="a" then
            return `self._0
        end
        if entryname=="b" then
            return `self._1
        end
    end)
    
    interval.staticmethods.unit = terra()
        return interval{0, 1}
    end

    interval.staticmethods.intersection = terra(I : &interval, J : &interval)
        return interval{tmath.max(I.a, J.a), tmath.min(I.b, J.b)}
    end

    interval.metamethods.__apply = terra(self : &interval, x : T)
        return tmath.fusedmuladd(self.b-self.a, x, self.a)
    end

    interval.metamethods.__add = terra(self : &interval, x : T)
        return interval{self.a+x, self.b+x}
    end

    interval.metamethods.__sub = terra(self : &interval, x : T)
        return interval{self.a-x, self.b-x}
    end

    interval.methods.vol = terra(self : &interval)
        return self.b-self.a
    end

    return interval
end)

local Cube = terralib.memoize(function(T, N)

    local interval = Interval(T)

    local cube = terralib.types.newstruct("cube")
    
    for k=0,N-1 do
        cube.entries:insert({field = "_"..tostring(k), type = interval})
    end
    
    cube:setconvertible("tuple")
    function cube.metamethods.__typename(self)
        return ("cube(%s, %s)"):format(tostring(T),tostring(N))
    end
    --add methods, staticmethods and templates tablet and template fallback mechanism 
    --allowing concept-based function overloading at compile-time
    base.AbstractBase(cube)
    

    cube.staticmethods.unit = terra()
        var C : cube
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    C.[s].a = 0
                    C.[s].b = 1
                end
            end
        end
        return C
    end

    cube.staticmethods.intersection = terra(A : &cube, B : &cube)
        var C : cube
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    C.[s] = interval.intersection(&A.[s], &B.[s])
                end
            end
        end
        return C
    end

    cube.metamethods.__apply = terra(self : &cube, x : ntuple(T,N))
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    x.[s] = self.[s](x.[s])
                end
            end
        end
        return x
    end

    cube.metamethods.__add = terra(self : &cube, x : ntuple(T,N))
        var C : cube
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    C.[s] = self.[s] + x.[s]
                end
            end
        end
        return C
    end

    cube.metamethods.__sub = terra(self : &cube, x : ntuple(T,N))
        var C : cube
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    C.[s] = self.[s] - x.[s]
                end
            end
        end
        return C
    end

    cube.methods.vol = terra(self : &cube)
        var vol = 1.0
        escape
            for k=0,N-1 do
                local s = "_"..tostring(k)
                emit quote
                    vol = vol * self.[s]:vol()
                end
            end
        end
        return vol
    end
    
    return cube
end)

local function Integrand(args)

    local A = args.domain_a
    local B = args.domain_b
    local C = geo.Hypercube.intersection(A, B)

    --intersection is empty, perform standard tensor product quadrature
    if C==nil then

        local struct integral{
            x : A
            y : B
        }
        return integral

    --intersectiion is non-empty, perform singular quadrature
    else
        
        local P_a, P_b = geo.ProductPair.new(C, A / C), geo.ProductPair.new(C, B / C)
        local struct integral{
            x : geo.ProductPair.mapping{domain=P_a}
            y : geo.ProductPair.mapping{domain=P_b}
        }

        --treat different cases
        local N = C:rangedim()
        local K = C:dim()

        --operations on intervals and cubes at runtime
        local interval = Interval(T)
        local cube_t = Cube(T,K)

        local function generate_quadrature_kernel(K)
            --compute local coordinates
            local relative_to_global_coords = terra(z : ntuple(T,K), u : ntuple(T,K))
                escape
                    for k=0,K-1 do
                        local s = "_"..tostring(k)
                        emit quote u.[s] = u.[s] + z.[s] end
                    end
                end
                return u
            end
            --pullback evaluation kernel to regularized coordinates
            local nktup, ktup = ntuple(T,N-K), ntuple(T,K)
            local terraform evaluate(self : &integral, mapping, kernel, 
                    u_tilde : nktup, v_tilde : nktup, z_hat : ktup, u_hat : ktup)
                var v_hat = relative_to_global_coords(z_hat, u_hat)
                var xhat, yhat = self.x(u_hat, u_tilde), self.y(v_hat, v_tilde)
                var x, y = mapping:xcoord(xhat, yhat), mapping:ycoord(xhat, yhat)
                var vol_x, vol_y = self.x:vol(u_hat, u_tilde), self.y:vol(v_hat, v_tilde)
                return kernel(x, y) * vol_x * vol_y
            end
            --generate the quadrature kernel
            local quadrature_kernel_imp
            if K==0 then
                terraform quadrature_kernel_imp(self : &integral, mapping, kernel, npts : int)
                    var alloc : Default
                    var alpha = kernel.alpha + 2*N - K - 1
                    var gausrule = gauss.legendre(&alloc, npts, interval{0.0, 1.0})
                    var S_1 = gauss.jacobi(&alloc, npts, 0.0, alpha, interval{0.0, 1.0})
                    var Q_5 = gauss.productrule(gausrule, gausrule, gausrule, gausrule, gausrule)
                    var result : T = 0.0
                    escape
                        local I = geo.Interval.new(0,1)
                        local cube = geo.Hypercube.new(I,I,I,I,I,I)
                        --iterate over pyramids in 'cube'
                        local apex = cube({0,0,0,0,0,0})
                        for pyramid_type in geo.Pyramid.decomposition{cube=cube, apex=apex} do
                            --generate mapping type
                            local pyramid_mapping = geo.Pyramid.mapping{domain=pyramid_type}
                            emit quote
                                var P : pyramid_mapping
                                --loop over singular direction
                                for qs in range.zip(&S_1.x, &S_1.w) do
                                    var s, ws = qs
                                    ws = ws / tmath.pow(s, alpha) --alpha is a static variable
                                    --loop over regular directions
                                    for qt in range.zip(&Q_5.x, &Q_5.w) do
                                        var t, wt = qt
                                        var p = P(t, s)
                                        var J = P:vol(t, s)
                                        var u_tilde, v_tilde = [&tuple(T,T,T)](&p._0), [&tuple(T,T,T)](&p._3)
                                        result = result + evaluate(self, mapping, kernel, @u_tilde, @v_tilde, {}, {}) * J * ws * wt
                                    end
                                end
                            end --emit quote
                        end
                    end --escape
                    return result
                end
            elseif K==1 then
                terraform quadrature_kernel_imp(self : &integral, mapping, kernel, npts : int)
                    var alloc : DefaultAllocator
                    var alpha = kernel.alpha + 2*N - K - 1
                    var gausrule = gauss.legendre(&alloc, npts, interval{0.0, 1.0})
                    var S_1 = gauss.jacobi(&alloc, npts, 0.0, alpha, interval{0.0, 1.0})
                    var Q_1 = gauss.productrule(gausrule)
                    var Q_4 = gauss.productrule(gausrule, gausrule, gausrule, gausrule)
                    var unitcube = cube_t.unit()
                    var result : double = 0.0
                    escape
                        local I = geo.Interval.new(0, 1)
                        local Z = {geo.Interval.new(-1, 0), geo.Interval.new(0, 1)}
                        for k,K in ipairs(Z) do
                            local cube = geo.Hypercube.new(I,I,I,I,K)
                            --iterate over pyramids in 'cube'
                            for pyramid_type in geo.Pyramid.decomposition{cube=cube, apex={0,0,0,0,0}} do
                                --generate mapping type
                                local pyramid_mapping = geo.Pyramid.mapping{domain=pyramid_type}
                                emit quote
                                    var P : pyramid_mapping
                                    --loop over singular direction
                                    for qs in range.zip(&S_1.x, &S_1.w) do
                                        var s, ws = qs; ws = ws / tmath.pow(s, alpha) --alpha is a static variable
                                        --loop over regular directions
                                        for qt in range.zip(&Q_4.x, &Q_4.w) do
                                            var t, wt = qt
                                            var p = P(t, s)
                                            var u_tilde, v_tilde, z = [&tuple(T,T)](&p._0), [&tuple(T,T)](&p._2), [&tuple(T)](&p._4)
                                            var J = P:vol(t, s)
                                            var shiftedcube = unitcube - @z
                                            var F = cube_t.intersection(&unitcube, &shiftedcube)
                                            var vol = F:vol()
                                            for qu in range.zip(&Q_1.x, &Q_1.w) do
                                                var u, wu = F(qu._0), vol * qu._1
                                                result = result + evaluate(self, mapping, kernel, @u_tilde, @v_tilde, @z, u) * J * ws * wt * wu
                                            end
                                        end
                                    end
                                end --emit quote
                            end
                        end
                    end --escape
                    return result
                end
            elseif K==2 then
                terraform quadrature_kernel_imp(self : &integral, mapping : &G, kernel : &F, npts : int) where {G, F}
                    var alloc : DefaultAllocator
                    var alpha = kernel.alpha + 2*N - K - 1
                    var gausrule = gauss.legendre(&alloc, npts, interval{0.0, 1.0})
                    var S_1 = gauss.jacobi(&alloc, npts, 0.0, alpha, interval{0.0, 1.0})
                    var Q_2 = gauss.productrule(gausrule, gausrule)
                    var Q_3 = gauss.productrule(gausrule, gausrule, gausrule)
                    var unitcube = cube_t.unit()
                    var result : double = 0.0
                    escape
                        local I = geo.Interval.new(0, 1)
                        local Z = {geo.Interval.new(-1, 0), geo.Interval.new(0, 1)}
                        for k,K in ipairs(Z) do
                            for j,J in ipairs(Z) do
                                local cube = geo.Hypercube.new(I,I,J,K)
                                --iterate over pyramids in 'cube'
                                for pyramid_type in geo.Pyramid.decomposition{cube=cube, apex={0,0,0,0}} do
                                    --generate mapping type
                                    local pyramid_mapping = geo.Pyramid.mapping{domain=pyramid_type}
                                    emit quote
                                        var P : pyramid_mapping
                                        --loop over singular direction
                                        for qs in range.zip(&S_1.x, &S_1.w) do
                                            var s, ws = qs; ws = ws / tmath.pow(s, alpha) --alpha is a static variable
                                            --loop over regular directions
                                            for qt in range.zip(&Q_3.x, &Q_3.w) do
                                                var t, wt = qt
                                                var p = P(t, s)
                                                var u_tilde, v_tilde, z = [&tuple(T)](&p._0), [&tuple(T)](&p._1), [&tuple(T,T)](&p._2)
                                                var J = P:vol(t, s)
                                                var shiftedcube = unitcube - @z
                                                var F = cube_t.intersection(&unitcube, &shiftedcube)
                                                var vol = F:vol()
                                                for qu in range.zip(&Q_2.x, &Q_2.w) do
                                                    var u, wu = F(qu._0), vol * qu._1
                                                    result = result + evaluate(self, mapping, kernel, @u_tilde, @v_tilde, @z, u) * J * ws * wt * wu
                                                end
                                            end
                                        end
                                    end --emit quote
                                end
                            end
                        end
                    end --escape
                    return result
                end
            elseif K==3 then
                terraform quadrature_kernel_imp(self : &integral, mapping : &G, kernel : &F, npts : int) where {G, F}
                    var alloc : DefaultAllocator
                    var alpha = kernel.alpha + 2*N - K - 1
                    var gausrule = gauss.legendre(&alloc, npts, interval{0.0, 1.0})
                    var S_1 = gauss.jacobi(&alloc, npts, 0.0, alpha, interval{0.0, 1.0})
                    var Q_2 = gauss.productrule(gausrule, gausrule)
                    var Q_3 = gauss.productrule(gausrule, gausrule, gausrule)
                    var unitcube = cube_t.unit()
                    var result : double = 0.0
                    escape
                        local Z = {geo.Interval.new(-1, 0), geo.Interval.new(0, 1)}
                        for _,K in ipairs(Z) do
                            for _,J in ipairs(Z) do
                                for _,I in ipairs(Z) do
                                    local cube = geo.Hypercube.new(I,J,K)
                                    --iterate over pyramids in 'cube'
                                    for pyramid_type in geo.Pyramid.decomposition{cube=cube, apex={0,0,0}} do
                                        --generate mapping type
                                        local pyramid_mapping = geo.Pyramid.mapping{domain=pyramid_type}
                                        emit quote
                                            var P : pyramid_mapping
                                            --loop over singular direction
                                            for qs in range.zip(&S_1.x, &S_1.w) do
                                                var s, ws = qs; ws = ws / tmath.pow(s, alpha) --alpha is a static variable
                                                --loop over regular directions
                                                for qt in range.zip(&Q_2.x, &Q_2.w) do
                                                    var t, wt = qt
                                                    var z = P(t, s)
                                                    var J = P:vol(t, s)
                                                    var shiftedcube = unitcube - z
                                                    var F = cube_t.intersection(&unitcube, &shiftedcube)
                                                    var vol = F:vol()
                                                    for qu in range.zip(&Q_3.x, &Q_3.w) do
                                                        var u, wu = F(qu._0), vol * qu._1
                                                        result = result + evaluate(self, mapping, kernel, {}, {}, z, u) * J * ws * wt * wu
                                                    end
                                                end
                                            end
                                        end --emit quote
                                    end
                                end
                            end
                        end
                    end --escape
                    return result
                end
            end -- if K
            --return the generated singular quadrature kernel
            return quadrature_kernel_imp
        end

        --generate the quadrature kernel
        local quadkernel = generate_quadrature_kernel(K)

        --API function that evaluates the integral
        terraform integral:eval(mapping, kernel, npts : int)
            return quadkernel(self, &mapping, &kernel, npts)
        end

        return integral
    end
    
end


return{
    Integrand = Integrand
}
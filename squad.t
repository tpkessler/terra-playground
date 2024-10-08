local io = terralib.includec("stdio.h")
local alloc = require('alloc')
local tmath = require('mathfuns')
local geo = require("geometry")
local vec = require("luavector")
local gauss = require("gauss")
local lambdas = require("lambdas")


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

local function Integrand(args)

    local kernel = args.kernel
    local A = args.domain_a
    local B = args.domain_b
    local C = geo.Hypercube.intersection(A, B)

    local integrant

    --intersection is empty, perform standard tensor product quadrature
    if C==nil then

        struct integrant{
            x : A
            y : B
        }
        return integrant

    --intersectiion is non-empty, perform singular quadrature
    else
        local P_a, P_b = geo.ProductPair.new(C, A / C), geo.ProductPair.new(C, B / C)
        struct integrant{
            x : geo.ProductPair.mapping{domain=P_a}
            y : geo.ProductPair.mapping{domain=P_b}
        }
        --treat different cases
        local N = C:rangedim()
        local K = C:dim()
        --compute local coordinates
        local V = terra(z : ntuple(T,K), u : ntuple(T,K))
            escape
                for k=0,K-1 do
                    local s = "_"..tostring(k)
                    emit quote u.[s] = u.[s] + z.[s] end
                end
            end
            return u
        end
        --pullback kernel to regularized coordinates. Here
        --(ǔ, v̌, û, ẑ) ∈ R⁶ with
        --ǔ ∈ Iᵈ⁻ᵏ
        --v̌ ∈ Iᵈ⁻ᵏ
        --ẑ ∈ Aᵏ = [-1,1]ᵏ
        --û ∈ Fᵏ = Iᵏ ∩ (Iᵏ - ẑ)
        terra integrant:evaluate(u_tilde : ntuple(T,N-K), v_tilde : ntuple(T,N-K), z_hat : ntuple(T,K), u_hat : ntuple(T,K))
            var v_hat = V(z_hat, u_hat)
            var x, y = self.x(u_hat, u_tilde), self.y(v_hat, v_tilde)
            var vol_x, vol_y = self.x:vol(u_hat, u_tilde), self.y:vol(v_hat, v_tilde)
            return kernel(x, y) * vol_x * vol_y
        end

        terra integrant:integrate()

        end

    end
    return integrant
end


local kernel = terra(x : T[3], y : T[3])
    return 1.0
end

local A = geo.Hypercube.new(geo.Interval.new(0,1), geo.Interval.new(0,1), geo.Interval.new(0,1))
local B = geo.Hypercube.new(geo.Interval.new(1,2), geo.Interval.new(1,2), geo.Interval.new(1,2))

local integrand = Integrand{kernel=kernel, domain_a=A, domain_b=B}


local terra integrate_imp_pyramid_dd()


end



terra integrate_imp_dd(alloc : Allocator, npts : size_t, alpha : double)
    var gausrule = gauss.rule("legendre", interval{a=0.0, b=1.0}, &alloc, npts)
    var Q_1 = gauss.rule("jacobi", interval{a=0.0, b=1.0}, &alloc, npts, 0.0, alpha)
    var Q_2 = gauss.productrule(gausrule, gausrule)
    var Q_3 = gauss.productrule(gausrule, gausrule, gausrule)
    var s : double = 0.0
    escape
        local Z = {geo.Interval(-1, 0), geo.Interval(0, 1)}
        for k,K in ipairs(Z) do
            for j,J in ipairs(Z) do
                for i,I in ipairs(Z) do
                    local cube = geo.Hypercube.new(I,J,K)
                    --iterate over pyramids in 'cube'
                    for pyramid_type in geo.Pyramid.decomposition{cube=cube, apex={0,0,0}} do
                        --generate mapping type
                        local pyramid_mapping = geo.Pyramid.mapping{domain=pyramid_type}
                        emit quote
                            var P : pyramid_mapping
                            --loop over singular direction
                            for qs in range.zip(&Q_1.x, &Q_1.w) do
                                var s, ws = qs; ws = ws / tmath.pow(s, alpha)
                                --loop over regular directions
                                for qt in range.zip(&Q_2.x, &Q_2.w) do
                                    var t, wt
                                    var z = P(t, s)
                                    var J = P:vol(t, s)
                                end
                            end
                        end
                    end
                end
            end
        end
    end --escape
    return s
end

local DefaultAllocator =  alloc.DefaultAllocator()

terra main()
    var alloc : DefaultAllocator
    var Q = gauss.rule("legendre",&alloc, 6)

    var J : integrand
    --var z = J:integrand({1.}, {1.}, {0.0,0.0}, {0.0,0.0})
    var z = J:evaluate({1.0,1.0,1.0}, {1.,1.0,1.0}, {}, {})
    io.printf("v = %0.2f\n", z)
end
main()
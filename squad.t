local io = terralib.includec("stdio.h")
local geo = require("geometry")
local gauss = require("gauss")
local lambdas = require("lambdas")

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

local function Integral(args)

    local kernel = args.kernel
    local A = args.domain_a
    local B = args.domain_b
    local C = geo.Hypercube.intersection(A, B)

    local integral

    if C==nil then

        struct integral{
            x : A
            y : B
        }
        return integral
    else
        local P_a, P_b = geo.ProductPair.new(C, A / C), geo.ProductPair.new(C, B / C)
        struct integral{
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
        terra integral:integrand(u_tilde : ntuple(T,N-K), v_tilde : ntuple(T,N-K), z_hat : ntuple(T,K), u_hat : ntuple(T,K))
            var v_hat = V(z_hat, u_hat)
            var x, y = self.x(u_hat, u_tilde), self.y(v_hat, v_tilde)
            var vol_x, vol_y = self.x:vol(u_hat, u_tilde), self.y:vol(v_hat, v_tilde)
            return kernel(x, y) * vol_x * vol_y
        end

        terra integral:evaluate()

        end

    end
    return integral
end


local kernel = terra(x : T[3], y : T[3])
    return 1.0
end


local A = geo.Hypercube.new(geo.Interval.new(0,1), geo.Interval.new(0,1), geo.Interval.new(0,1))
local B = geo.Hypercube.new(geo.Interval.new(1,2), geo.Interval.new(1,2), geo.Interval.new(1,2))

local integral = Integral{kernel=kernel, domain_a=A, domain_b=B}


terra main()
    var J : integral
    --var z = J:integrand({1.}, {1.}, {0.0,0.0}, {0.0,0.0})
    var z = J:integrand({1.0,1.0,1.0}, {1.,1.0,1.0}, {}, {})
    io.printf("v = %0.2f\n", z)
end
main()
local base = require("base")
local concepts = require("concepts")
local tmath = require("tmath")

import "terraform"

local Real = concepts.Real
local Number = concepts.Number
local Integer = concepts.Integer
local Vector = concepts.Vector

-- C: A callable of signature {x: &V, r: &V} -> {} that takes input x and
--    puts the computed result into r
--
-- dC: A callable of signature {x: &V, b: &V, t: &V} -> {} that takes input x,
--     right hand side b and puts the solution of f'(x) t = b into t. 
local terraform affine(
    residual: C,
    invjacobian: dC,
    x: &V,
    tol: T,
    kmax: I,
    lambda0: T,
    lambdamin: T
) where {
    C, dC, V: Vector(Number), T: Real, I: Integer
}
    --[=[
    Affine globalized Newton method. Adapted from pp 148-9 in
    Peter Deuflhard, Newton Mtehods for Nonlinear Problems, Springer Verlag, 2004
    --]=]
    -- residual
    var f = x:like()
    -- new guess
    var xnew = x:like()
    -- Newton update
    var dx = x:like()
    -- Old Newton update
    var dxold = x:like()
    -- Next guess for update
    var dxbar = x:like()
    -- Auxilliary vector
    var dxp = x:like()

    var lambda = lambda0
    for k = 0, kmax do
        -- Compute a first guess for the new update by solving
        -- 
        -- dF(x_k) dx_k = -F(x_k)
        -- 
        -- for dx_k
        residual(x, &f)
        f:scal([V.traits.eltype](-1))
        dx:fill([V.traits.eltype](tol))
        invjacobian(x, &f, &dx)

        -- dx serves as an error estimate. If it's below our tolerance,
        -- we found our solution.
        if dx:norm() < tol then
            x:axpy([V.traits.eltype](1), &dx)
            return
        end

        -- Compute an esimate of the Lipschitz constant of dF
        if k > 0 then
            dxp:copy(&dxbar)
            dxp:axpy([V.traits.eltype](-1), &dx)
            var mu = (
                dxold:norm() * dxbar:norm() / (dxp:norm() * dx:norm()) * lambda
            )
            lambda = tmath.min([T](1), mu)
        end

        -- Globalization step. Find the next step size in a trust region fashion
        while lambda > lambdamin do
            -- Compute an esimate for the new update by solving
            -- 
            -- dF(x_k) dxbar = -F(xnew)
            -- 
            -- for dxbar. Note that the Jacobian is evaluated at the old iterate.
            xnew:copy(x)
            xnew:axpy(lambda, &dx)
            residual(&xnew, &f)
            f:scal([V.traits.eltype](-1))
            invjacobian(x, &f, &dxbar)

            var theta = dxbar:norm() / dx:norm()

            dxp:copy(&dxbar)
            dxp:axpy(lambda - 1, &dx)
            var mup = dx:norm() * lambda * lambda / 2 / dxp:norm()

            -- Check for convergence of line search
            if theta >= [T](1) then
                -- Line search failed. Reduce the step size and continue
                -- with the regularity check.
                lambda = tmath.min(mup, lambda / 2)
                lambda = tmath.max(lambda, lambdamin)
            else
                -- Line search terminated, we accept the update.
                x:copy(&xnew)
                dxold:copy(&dx)

                -- Check for convergence of the Newton iteration.
                var lambdap = tmath.min([T](1), mup)
                if (
                    lambda == [T](1)
                    and lambdap == [T](1)
                    and dxbar:norm() < tol
                ) then
                    -- We found our solution!
                    x:axpy([V.traits.eltype](1), &dxbar)
                    goto converged
                else
                    -- Exit line search and continue with the next Newton iteration.
                    break
                end -- line search converged
            end -- line search convergence check
        end -- line search iteration
    end -- Newton iteration
    ::converged::
end


return {
    affine = affine,
}

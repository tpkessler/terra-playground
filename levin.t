local complex = require("complex")
local math = terralib.includec("math.h")
local lib = terralib.includec("stdlib.h")
local io = terralib.includec("stdio.h")
local blas = require("blas")
local lapack = require("lapack")
local time = require("timing")
local err = require("assert")
terralib.linklibrary("libopenblas.so")

local function alloc(T)
  local terra impl(n: uint64)
    var ptr = [&T](lib.malloc(sizeof(T) * n))
    err.assert(ptr ~= nil)
    return ptr
  end
  return impl
end

local complexDouble = complex.complex(double)
local allocDouble = alloc(double)
local allocComplexDouble = alloc(complexDouble)

local terra cheb_nodes(n: int, a: double, b: double, x: &double)
  var pi = 4.0 * math.atan(1.0)
  for i = 0, n do
    var arg = 1.0 * (n - i - 1) / (n - 1) * pi
    x[i] = (a + b) / 2 + (b - a) / 2 * math.cos(arg)
  end
end

local terra cheb_col(n: int, a: &double)
  var x = allocDouble(n)
  cheb_nodes(n, -1.0, 1.0, x)

  for i = 0, n do
    a[n * i] = 1.0
  end

  if n > 1 then
    for i = 0, n do
      a[1 + n * i] = x[i]
    end
  end

  for j = 2, n do
    for i = 0, n do
      a[j + n * i] = 2.0 * x[i] * a[j - 1 + n * i] - a[j - 2 + n * i]
    end
  end

  lib.free(x)
end

local terra der_cheb_col(n: int, a: &double)
  var x = allocDouble(n)
  defer lib.free(x)
  cheb_nodes(n, -1.0, 1.0, x)

  for i = 0, n do
    a[n * i] = 0.0
  end

  if n == 1 then
    return
  end

  if n > 1 then
    for i = 0, n do
      a[1 + n * i] = 1.0
    end
  end

  if n > 2 then
    for i = 0, n do
      a[2 + n * i] = 2.0 * x[i]
    end
  end

  for j = 3, n do
    for i = 0, n do
      a[j + n * i] = 2.0 * x[i] * a[j - 1 + n * i] - a[j - 2 + n * i]
    end
  end

  for j = 0, n do
    for i = 0,n do
      a[j + n * i] = j * a[j + n * i]
    end
  end

end


local terra sph_j0(x: double)
  return math.sin(x) / x
end

local terra sph_j1(x: double)
  return (sph_j0(x) - math.cos(x)) / x
end

local terra w(x: double, k: double, res: &complexDouble)
  var pi = 4.0 * math.atan(1.0)
  var fac = math.sqrt(2.0 / pi)
  -- Evaluates Bessel functions at half integers.
  res[0] = fac * sph_j0(k * x) * math.sqrt(k * x)
  res[1] = fac * sph_j1(k * x) * math.sqrt(k * x)
end

local terra A(x: double, k: double, res: &complexDouble)
  var nu = 1.0 + 0.5

  res[0] = (nu - 1) / x
  res[1] = -k
  res[2] = k
  res[3] = -nu / x
end

local terra f(x: double, res: &complexDouble)
  res[0] = 0.0
  res[1] = 1.0 / (1.0 + x * x)
end

local terra svd(n: int, a: &complexDouble, lda: int, s: &double,
                u: &complexDouble, ldu: int, vt: &complexDouble, ldvt: int)
  var superb = allocDouble(n)
  defer lib.free(superb)
  var info = lapack.gesvd(lapack.ROW_MAJOR, @'A', @'A', n, n, a, lda,
                          s, u, ldu, vt, ldvt, superb)
  return info
end

local terra svd_solve(n: int, s: &double, u: &complexDouble, ldu: int,
                      vt: &complexDouble, ldvt: int, x: &complexDouble, incx: int)
  var tol = 1e-15
  var rank = 0
  while rank < n and s[rank] > tol * s[0] do
    rank = rank + 1
  end
  var aux = allocComplexDouble(rank)
  defer lib.free(aux)
  blas.gemv(blas.RowMajor, blas.ConjTrans, n, rank, 1.0, u, ldu, x, incx, 0.0, aux, 1)
  for k = 0, rank do
    aux[k] = aux[k] / s[k]
  end
  blas.gemv(blas.RowMajor, blas.ConjTrans, rank, n, 1.0, vt, ldvt, aux, 1, 0.0, x, incx)
end

local terra qrp(n: int, r: &complexDouble, ldr: int, jpvt: &int, tau: &complexDouble)
  var info = lapack.geqp3(lapack.ROW_MAJOR, n, n, r, ldr, jpvt, tau)
  return info
end

local terra qrp_solve(n: int, r: &complexDouble, ldr: int, jpvt: &int,
                      tau: &complexDouble, x: &complexDouble, incx: int)
  var tol = 1e-15
  var rank = 0
  while rank < n and r[rank + ldr * rank]:norm() > tol * r[0]:norm() do
    rank = rank + 1
  end
  var y = allocComplexDouble(n)
  defer lib.free(y)
  blas.copy(n, x, incx, y, 1)
  var info = lapack.ormqr(lapack.ROW_MAJOR, @'L', @'C', n, 1, n, r, ldr, tau, y, 1)
  blas.trsv(blas.RowMajor, blas.Upper, blas.NoTrans, blas.NonUnit, rank,
            r, ldr, y, 1)
  for i = rank, n do
    y[i] = 0.0
  end
  for i = 0, n do
    x[ jpvt[i] - 1] = y[i]
  end
  return info
end

local USE_SVD = false
local allocInt = alloc(int)
local terra levin(s: int, k: double, n: int, a: double, b: double,
                  L: double)

  var val = allocDouble(n * n)
  defer lib.free(val)
  cheb_col(n, val)

  var der = allocDouble(n * n)
  defer lib.free(der)
  der_cheb_col(n, der)

  var x = allocDouble(n)
  defer lib.free(x)
  cheb_nodes(n, a, b, x)

  var ld = n * s
  var sys = allocComplexDouble(ld * ld)
  defer lib.free(sys)
  var aloc = allocComplexDouble(s * s)
  defer lib.free(aloc)
  for i = 0, n do
    A(x[i], L * k, aloc)
    for alpha = 0, s do
      var idx = alpha + s * i
      for j = 0, n do
        for beta = 0, s do
          var jdx = beta + s * j
          var aux = aloc[beta * s + alpha] * val[i * n + j]
          if alpha == beta then
            aux = aux + 2.0 / (b - a) * der[i * n + j] 
          end
          sys[jdx + ld * idx] = aux
        end
      end
    end
  end

  var rhs = allocComplexDouble(ld)
  defer lib.free(rhs)
  for i = 0, n do
    f(L * x[i], rhs + s * i)    
  end

  if USE_SVD then
    var sigma = allocDouble(ld)
    defer lib.free(sigma)
    var u = allocComplexDouble(ld * ld)
    defer lib.free(u)
    var vt = allocComplexDouble(ld * ld)
    svd(ld, sys, ld, sigma, u, ld, vt, ld)
    svd_solve(ld, sigma, u, ld, vt, ld, rhs, 1)
  else
    var tau = allocComplexDouble(ld)
    defer lib.free(tau)
    var jpvt = allocInt(ld)
    defer lib.free(jpvt)
    for i = 0, ld do
      jpvt[i] = 0
    end
    qrp(ld, sys, ld, jpvt, tau)
    qrp_solve(ld, sys, ld, jpvt, tau, rhs, 1)
  end

  var wb = allocComplexDouble(s)
  defer lib.free(wb)
  w(b, L * k, wb)

  var res = complexDouble(0.0)
  for alpha = 0, s do
    var sum = complexDouble(0.0)
    for i = 0, n do
      sum = sum + rhs[s * i + alpha]
    end
    res = res + wb[alpha] * sum
  end

  w(a, L * k, wb)
  for alpha = 0, s do
    var sum = complexDouble(0.0)
    for i = 0, n do
      if i % 2 == 0 then
        sum = sum + rhs[s * i + alpha]
      else
        sum = sum - rhs[s * i + alpha]
      end
    end
    res = res - wb[alpha] * sum
  end

  return L * res

end

local bires = tuple(double, double, complexDouble)
local allocBires = alloc(bires)

local terra adaptive_levin(s: int, k: double, n: int, a: double, b: double,
                           L: double, tol: double)
  var val = complexDouble(0.0)
  var val0 = levin(s, k, n, a, b, L)
  -- HACK size has to grow dynamically
  var buf = 2028
  var interval = allocBires(buf)
  defer lib.free(interval)
  interval[0] = {a, b, val0}
  var size = 1
  while size > 0 and size < buf - 2 do
    var a0, b0, val0 = unpacktuple(interval[size - 1])
    size = size - 1
    var c0 = (a0 + b0) / 2
    var valL = levin(s, k, n, a0, c0, L)
    var valR = levin(s, k, n, c0, b0, L)
    if (val0 - valL - valR):norm() < tol then
      val = val + val0
    else
      interval[size] = {a0, c0, valL}
      size = size + 1
      interval[size] = {c0, b0, valR}
      size = size + 1
    end
  end

  return val
end

local terra main()
  var tol = 1e-15
  var s = 2
  var a = tol
  var b = 1.0
  var L = 100.0
  var n = 12
  var k = 2.5

  var sw = time.parallel_timer.new()
  sw:start()
  var res = adaptive_levin(s, k, n, a, b, L, tol)
  var t = sw:stop()

  io.printf("%.2e %.15e %.15e\n", t * 1e3, res:real(), res:imag())

  return 0
end

main()

terralib.saveobj("levin.o", {main = main})

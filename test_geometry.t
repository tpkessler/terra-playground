-- SPDX-FileCopyrightText: 2024 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

local vec = require("luavector")
local geo = require("geometry")

local size_t = uint64
local T = double

import "terratest/terratest"

testenv "Interval" do

    testset "static data" do
        local interval = geo.Interval.new(0,2)
        test [geo.Interval.isa(interval)]
        test [interval.eltype == T]
        test [interval.a == 0]
        test [interval.b == 2]
        test [interval:isinside(0) and interval:isinside(2) and not interval:isinside(-0.01) and not interval:isinside(2.01)]
    end

    testset "equality" do
        test [geo.Interval.new(0,2) == geo.Interval.new(0,2)]
        test [geo.Interval.new(0,2) ~= geo.Interval.new(0,1)]
    end

    testset "intersection - types" do
        local I = geo.Interval.new(0,2)
        local J = geo.Interval.new(1,3)
        local K = geo.Interval.new(2,4)
        local L = geo.Interval.new(3,5)
        test [geo.Interval.intersection(I,I)==I]
        test [geo.Interval.intersection(I,J)==geo.Interval.new(1,2)]
        test [geo.Interval.intersection(I,K)==2]
        test [geo.Interval.intersection(I,L)==nil]
    end

    testset "evaluation" do
        local interval = geo.Interval.new(1,3)
        test [interval(0) == 1]
        test [interval(1) == 3]
        test [interval(interval:barycentriccoord(1)) == 1]
        test [interval(interval:barycentriccoord(3)) == 3]
    end

    testset "addition / subtraction" do
        local I = geo.Interval.new(1,3)
        test [I + 1 == geo.Interval.new(2,4)]
        test [1 + I == geo.Interval.new(2,4)]
        test [I - 1 == geo.Interval.new(0,2)]
        test [1 - I == geo.Interval.new(-2,0)]
        test [-I == geo.Interval.new(-3,-1)]
    end

end

testenv "Hypercube - 3d" do

    local I, J, K = geo.Interval.new(0,1), geo.Interval.new(1,3), geo.Interval.new(2,5)

    testset "static data" do
        local Cube = geo.Hypercube.new(I, J, K)
        test [geo.Hypercube.isa(Cube)]
        test [Cube:dim()==3]
        test [Cube:rangedim()==3]
        test [Cube:vol()==6]
    end

    testset "intersection" do
        --lines
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, 0, 0), geo.Hypercube.new(0, I, 0)) == geo.Hypercube.new(0, 0, 0)]
        --volumes
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, I, I), geo.Hypercube.new(I, I, I)) == geo.Hypercube.new(I, I, I)]
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, I, I), geo.Hypercube.new(J, I, I)) == geo.Hypercube.new(1, I, I)]
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, I, I), geo.Hypercube.new(J, J, I)) == geo.Hypercube.new(1, 1, I)]
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, I, I), geo.Hypercube.new(J, J, J)) == geo.Hypercube.new(1, 1, 1)]
        test [geo.Hypercube.intersection(geo.Hypercube.new(I, I, I), geo.Hypercube.new(K, J, J)) == nil]
    end

    testset "mul" do
        local L1, L2, L3 = geo.Hypercube.new(I, J.a, K.a), geo.Hypercube.new(I.a, J, K.a), geo.Hypercube.new(I.a, J.a, K)
        test [L1*L2*L3 == geo.Hypercube.new(I, J, K)]
    end

    testset "div" do
        local A = geo.Hypercube.new(geo.Interval.new(0,2), geo.Interval.new(0,1), geo.Interval.new(0,1))
        local B = geo.Hypercube.new(0, geo.Interval.new(0,1), geo.Interval.new(0,1))
        local C = geo.Hypercube.new(geo.Interval.new(0,2), 0, 0)
        test [(B * C) == A]
        test [(B * C) / C == B]
        test [(B * C) / B == C]
    end

    testset "evaluation" do
        local Cube = geo.Hypercube.new(I, J, K)
        test [Cube({0,0,0}) == vec.new{0,1,2}] 
        test [Cube({1,1,1}) == vec.new{1,3,5}]
        test [Cube(Cube:barycentriccoords{0,1,2}) == vec.new{0,1,2}]
    end

    testset "addition / subtraction" do
        local Cube = geo.Hypercube.new(I, J, K)
        test [Cube + {0,1,2} == geo.Hypercube.new(I, J+1, K+2)]
        test [{0,1,2} + Cube == geo.Hypercube.new(I, J+1, K+2)]
        test [Cube - {0,1,2} == geo.Hypercube.new(I, J-1, K-2)]
        test [{0,1,2} - Cube == geo.Hypercube.new(-I, -J+1, -K+2)]
        test [-Cube == geo.Hypercube.new(-I, -J, -K)]
    end
end

testenv "Hypercube mapping - 3d - line" do

    --compute hypercube at compile-time
    local Line = geo.Hypercube.new(1, geo.Interval.new(2,4), 2)
    
    --compute mappings at compile-time
    local F = geo.Hypercube.mapping{domain=Line} -- origin={1,2,2}
    local G = geo.Hypercube.mapping{domain=Line, origin={1,4,2}}

    testset "properties" do
        test [F.ismapping]
        test [F.domain:dim()==1]
        test [F.domain:rangedim()==3]
    end

    terracode
        var f : F
        var g : G
    end

    testset "evaluation" do
        terracode
            var a = f({0})
            var b = f({1})
        end
        test a[0]==1 and a[1]==2 and a[2]==2
        test b[0]==1 and b[1]==4 and b[2]==2
    end

    testset "evaluation - reversed origin" do
        terracode
            var a = g({0})
            var b = g({1})
        end
        test a[0]==1 and a[1]==4 and a[2]==2
        test b[0]==1 and b[1]==2 and b[2]==2
    end

    testset "barycentric coordinates" do
        terracode
            var a = f:barycentriccoord({1,2,2})
            var b = f:barycentriccoord({1,4,2})
        end
        test a._0==0
        test b._0==1
    end

    testset "barycentric coordinates - reversed origin" do
        terracode
            var a = g:barycentriccoord({1,2,2})
            var b = g:barycentriccoord({1,4,2})
        end
        test a._0==1
        test b._0==0
    end

end

testenv "Hypercube mapping - 3d - surface" do

    --compute hypercube at compile-time
    local Surf = geo.Hypercube.new(1, geo.Interval.new(2,4), geo.Interval.new(5,6))
    
    --compute mappings at compile-time
    local F = geo.Hypercube.mapping{domain=Surf} --origin={1,2,5}
    local G = geo.Hypercube.mapping{domain=Surf, origin={1,4,6}}

    testset "properties" do
        test [F.ismapping]
        test [F.domain:dim()==2]
        test [F.domain:rangedim()==3]
    end

    terracode
        var f : F
        var g : G
    end

    testset "evaluation" do
        terracode
            var a = f({0,0})
            var b = f({1,1})
        end
        test a[0]==1 and a[1]==2 and a[2]==5
        test b[0]==1 and b[1]==4 and b[2]==6
    end

    testset "evaluation - reversed origin" do
        terracode
            var a = g({0,0})
            var b = g({1,1})
        end
        test a[0]==1 and a[1]==4 and a[2]==6
        test b[0]==1 and b[1]==2 and b[2]==5
    end

    testset "barycentric coordinates" do
        terracode
            var a = f:barycentriccoord({1,2,5})
            var b = f:barycentriccoord({1,4,6})
        end
        test a._0==0 and a._1==0
        test b._0==1 and b._1==1
    end

    testset "barycentric coordinates - reversed origin" do
        terracode
            var a = g:barycentriccoord({1,2,5})
            var b = g:barycentriccoord({1,4,6})
        end
        test a._0==1 and a._1==1
        test b._0==0 and b._1==0
    end

end

testenv "Hypercube mapping - 3d - volume" do

    --compute hypercube at compile-time
    local Vol = geo.Hypercube.new(geo.Interval.new(0,1), geo.Interval.new(2,4), geo.Interval.new(5,6))
    
    --compute mappings at compile-time
    local F = geo.Hypercube.mapping{domain=Vol} --origin={0,2,5}
    local G = geo.Hypercube.mapping{domain=Vol, origin={1,4,6}}

    testset "properties" do
        test [F.ismapping]
        test [F.domain:dim()==3]
        test [F.domain:rangedim()==3]
    end

    terracode
        var f : F
        var g : G
    end

    testset "evaluation" do
        terracode
            var a = f({0,0,0})
            var b = f({1,1,1})
        end
        test a[0]==0 and a[1]==2 and a[2]==5
        test b[0]==1 and b[1]==4 and b[2]==6
    end

    testset "evaluation - reversed origin" do
        terracode
            var a = g({0,0,0})
            var b = g({1,1,1})
        end
        test a[0]==1 and a[1]==4 and a[2]==6
        test b[0]==0 and b[1]==2 and b[2]==5
    end

    testset "barycentric coordinates" do
        terracode
            var a = f:barycentriccoord({0,2,5})
            var b = f:barycentriccoord({1,4,6})
        end
        test a._0==0 and a._1==0 and a._2==0
        test b._0==1 and b._1==1 and b._2==1
    end

    testset "barycentric coordinates - reversed origin" do
        terracode
            var a = g:barycentriccoord({0,2,5})
            var b = g:barycentriccoord({1,4,6})
        end
        test a._0==1 and a._1==1 and a._2==1
        test b._0==0 and b._1==0 and b._2==0
    end

end

testenv "Pyramid - 2D" do

    local base = geo.Hypercube.new(3, geo.Interval.new(0,1))
    local apex = vec.new{1,0}

    local P = geo.Pyramid.new{base=base, apex=apex}

    testset "properties" do
        test [P:dim() == 2]
        test [P:height() == 2]
        test [P:vol() == 1]
    end

    testset "decomposition" do
        local cube = geo.Hypercube.new(geo.Interval.new(0,1), geo.Interval.new(0,1))
        local area = 0.0
        local iter = geo.Pyramid.decomposition{cube=cube, apex={0,0}}
        for P in iter do
            area = area + P:vol()
        end
        test [area == 1]
    end

    local mapping = geo.Pyramid.mapping{domain=P}

    testset "evaluation" do
        terracode
            var p : mapping
            var a = p({0}, 0)
            var b = p({0}, 1)
            var c = p({1}, 1)
        end
        test a._0==1 and a._1==0
        test b._0==3 and b._1==0
        test c._0==3 and c._1==1
    end

    testset "jacobian" do
        terracode
            var p : mapping
            var va = p:vol({0},0)
            var vb = p:vol({0},1)
            var vc = p:vol({1},1)
        end
        test va==0
        test vb==2
        test vc==2
    end

end

testenv "Pyramid - 3D" do

    --compute hypercube at compile-time
    local base = geo.Hypercube.new(4, geo.Interval.new(0,1), geo.Interval.new(0,1))
    local apex = vec.new{1,1,1}

    local P = geo.Pyramid.new{base=base, apex=apex}

    testset "properties" do
        test [P:dim() == 3]
        test [P:height() == 3]
        test [P:vol() == 1]
    end

    testset "decomposition" do
        local cube = geo.Hypercube.new(geo.Interval.new(1,2), geo.Interval.new(1,2), geo.Interval.new(1,2))
        local vol = 0.0
        local iter = geo.Pyramid.decomposition{cube=cube, apex={1,1,1}}
        for P in iter do
            vol = vol + P:vol()
        end
        test [math.abs(vol -1) < 1e-12]
    end

    local mapping = geo.Pyramid.mapping{domain=P}

    testset "evaluation" do
        terracode
            var p : mapping
            var a = p({0,0},0)
            var b = p({0,0},1)
            var c = p({1,1},1)
        end
        test a._0==1 and a._1==1 and a._2==1
        test b._0==4 and b._1==0 and b._2==0
        test c._0==4 and c._1==1 and c._2==1
    end

    testset "jacobian" do
        terracode
            var p : mapping
            var va = p:vol({0,0},0)
            var vb = p:vol({0,0},1)
            var vc = p:vol({1,1},1)
        end
        test va==0
        test vb==3
        test vc==3
    end

end

testenv "Pyramid - 6D" do

    --compute hypercube at compile-time
    local I = geo.Interval.new(0,1)
    local cube = geo.Hypercube.new(I,I,I,I,I,I)
    local apex = cube({0,0,0,0,0,0})
    local pyramids = geo.Pyramid.decomposition{cube=cube, apex=apex}

    testset "decomposition" do
        local vol = 0.0
        for P in pyramids do
            vol = vol + P:vol()
        end
        test [math.abs(vol -1) < 1e-12]
    end

end

testenv "ProductPair - 3d" do

    local I, J = geo.Interval.new(0,1), geo.Interval.new(1,2)
    
    testset "static data" do
        local X, Y = geo.Hypercube.new(I, I, I),  geo.Hypercube.new(J, I, I)
        local Z = geo.Hypercube.intersection(X, Y)
        local x = geo.ProductPair.new(X / Z, Z)
        local y = geo.ProductPair.new(Y / Z, Z)
        test [x~=nil and x.A:dim()==1 and x.B:dim()==2]
        test [y~=nil and y.A:dim()==1 and y.B:dim()==2]
    end

    testset "0-dimensional intersection" do
        local A, B = geo.Hypercube.new(I, I, I),  geo.Hypercube.new(J, J, J)
        local C = geo.Hypercube.intersection(A, B)
        local P_a = geo.ProductPair.new(C, A / C)
        local P_b = geo.ProductPair.new(C, B / C)
        terracode
            var prod_a : geo.ProductPair.mapping{domain=P_a, origin={1,1,1}}
            var prod_b : geo.ProductPair.mapping{domain=P_b, origin={1,1,1}}
            var y_a = prod_a({}, {0.1,0.2,0.3})
            var y_b = prod_b({}, {0.1,0.2,0.3})
            var vol_a = prod_a:vol({}, {0.1,0.2,0.3})
            var vol_b = prod_b:vol({}, {0.1,0.2,0.3})
        end
        test y_a[0]==0.9 and y_a[1]==0.8 and y_a[2]==0.7
        test y_b[0]==1.1 and y_b[1]==1.2 and y_b[2]==1.3
        test vol_a==1
        test vol_b==1
    end

    testset "1-dimensional intersection" do
        local A, B = geo.Hypercube.new(I, I, I),  geo.Hypercube.new(J, J, I)
        local C = geo.Hypercube.intersection(A, B)
        local P_a = geo.ProductPair.new(C, A / C)
        local P_b = geo.ProductPair.new(C, B / C)
        terracode
            var prod_a : geo.ProductPair.mapping{domain=P_a, origin={1,1,0}}
            var prod_b : geo.ProductPair.mapping{domain=P_b, origin={1,1,0}}
            var y_a = prod_a({0.1}, {0.2,0.3})
            var y_b = prod_b({0.1}, {0.2,0.3})
            var vol_a = prod_a:vol({0.1}, {0.2,0.3})
            var vol_b = prod_b:vol({0.1}, {0.2,0.3})
        end
        test y_a[0]==0.8 and y_a[1]==0.7 and y_a[2]==0.1
        test y_b[0]==1.2 and y_b[1]==1.3 and y_b[2]==0.1
        test vol_a==1
        test vol_b==1
    end
    local K, L = geo.Interval.new(1,3), geo.Interval.new(3,4)
    
    testset "2-dimensional intersection" do
        local A, B = geo.Hypercube.new(K, I, I),  geo.Hypercube.new(L, I, I)
        local C = geo.Hypercube.intersection(A, B)
        local P_a = geo.ProductPair.new(C, A / C)
        local P_b = geo.ProductPair.new(C, B / C)
        terracode
            var prod_a : geo.ProductPair.mapping{domain=P_a, origin={3,0,0}}
            var prod_b : geo.ProductPair.mapping{domain=P_b, origin={3,0,0}}
            var a_0 = prod_a({0.2,0.3},{0.0})
            var a_1 = prod_a({0.2,0.3},{1.0})
            var b_0 = prod_b({0.2,0.3},{0.0})
            var b_1 = prod_b({0.2,0.3},{1.0})
            var vol_a = prod_a:vol({0.2,0.3},{1.0})
            var vol_b = prod_b:vol({0.2,0.3},{1.0})
        end
        --points a
        test a_0[0]==3.0 and a_0[1]==0.2 and a_0[2]==0.3
        test a_1[0]==1.0 and a_1[1]==0.2 and a_1[2]==0.3
        test vol_a==2
        --points b
        test b_0[0]==3.0 and b_0[1]==0.2 and b_0[2]==0.3
        test b_1[0]==4.0 and b_1[1]==0.2 and b_1[2]==0.3
        test vol_b==1
    end

    testset "3-dimensional intersection" do
        local A = geo.Hypercube.new(K,I,J)
        local P = geo.ProductPair.new(A, A / A)
        terracode
            var prod : geo.ProductPair.mapping{domain=P, origin={1,0,1}}
            var a = prod({0.5,0.5,0.5},{})
            var vol = prod:vol({0.5,0.5,0.5},{})
        end
        test a[0]==2.0 and a[1]==0.5 and a[2]==1.5
        test vol==2 
    end

end
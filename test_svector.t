import "terratest/terratest"

local SVector = require('svector')
local nfloat = require("nfloat")
local io = terralib.includec("stdio.h")

local float1024 = nfloat.FixedFloat(1024)

for _,T in ipairs{int32,float,double, float1024} do
for N=1,6 do
    testenv(N, T) "Static vector" do

            local svec = SVector.StaticVector(T,N)   
         
            testset "new, size, get, set" do
                terracode
                    var v = svec.new()
                    for i=0,N do              
                        v:set(i, i+1)
                    end                     
                end
                test v:size()==N
                for i=0,N-1 do              
                    test v:get(i) == T(i+1)
                end 
            end
          
            testset "zeros" do                       
                terracode                                  
                    var v = svec.zeros()
                end
                test v:size()==N
                for i=0,N-1 do              
                    test v:get(i) == 0
                end 
            end 
        
            testset "ones" do                       
                terracode                                  
                    var v = svec.ones()
                end 
                test v:size()==N
                for i=0,N-1 do              
                    test v:get(i) == T(1)
                end 
            end 

            testset "all" do                       
                terracode                                  
                    var v = svec.all(T(3))
                end 
                test v:size()==N
                for i=0,N-1 do              
                    test v:get(i) == T(3)
                end 
            end 
            
        end --N

        testset "from (N=2)" do
            local svec = SVector.StaticVector(T, 2)
            terracode
                var v = svec.from(1, 2)
            end
            test v:size() == 2
            test v:get(0) == 1
            test v:get(1) == 2
        end

        testset "from (N=3)" do
            local svec = SVector.StaticVector(T, 3)
            terracode
                var v = svec.from(1, 2, 3)
            end
            test v:size() == 3
            test v:get(0) == 1
            test v:get(1) == 2
            test v:get(2) == 3
        end

        testset "copy (N=4)" do
            local svec = SVector.StaticVector(T, 4)
            terracode
                var v = svec.from(1, 2, 3, 4)
                var w = svec.new()
                w:copy(&v)
            end
            test w:size() == 4
            for i = 0, 3 do
                test w:get(i) == i + 1
            end
        end

        testset "axpy (N=5)" do
            local svec = SVector.StaticVector(T, 5)
            terracode
                var v = svec.from(1, 2, 3, 4, 5)
                var w = svec.from(5, 4, 3, 2, 1)
                w:axpy(1, &v)
            end
            test w:size() == 5
            for i = 0, 4 do
                test w:get(i) == 6
            end
        end

        testset "dot (N=6)" do
            local svec = SVector.StaticVector(T, 6)
            terracode
                var v = svec.from(1, 2, 3, 4, 5, 6)
                var w = svec.from(5, 4, 3, 2, 1, 0)
                var res = w:dot(&v)
            end
            test res == 35
        end

    end --T

end --testenv


--[[
testenv "Static vector" do

    for _,T in ipairs{int32} do
        for N=3,3 do

            local vec = SVector.StaticVector(T,N)   
         
            testset(N,T) "new, size, get, set" do
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
          
            testset(N,T) "zeros" do                       
                terracode                                  
                    var v = vec.zeros()
                    --for i=0,N do
                    --    v:set(i,0)
                    --end
                end
                test v:get(0) == 0
                test v:get(1) == 0
                test v:get(2) == 0
                --test v:get(4) == 0
            end 
        
            testset(N,T) "ones" do                       
                terracode                                  
                    var v = svec.ones()
                end 
                test v:size()==N
                for i=0,N-1 do              
                    test v:get(i) == T(1)
                end 
            end 

            testset(N,T) "fill" do                       
                terracode                                  
                    var v = svec.fill(T(3))
                    for i=0,N do
                        io.printf("value %d\n", v(i))
                        if v:get(i) == T(1) then
                            io.printf("test passed\n")
                            io.printf("value %f\n", [double](v(i)) - [double](1))
                        end
                    end
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
        --]]

    end --T

end --testenv
--]]
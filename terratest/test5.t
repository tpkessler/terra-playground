--local SVector = {}
 
SVector = terralib.memoize(function(T,N)
    local struct Vector{
        _data : T[N]
    }  
    local Class = {}
    Class.Vector = Vector

    terra Vector:size() : int
	return N 
    end

    Vector.metamethods.__apply = macro(function(self,idx)
        return `self._data[idx]
    end)

    terra Class.fill(a : T) : Vector
	var v : Vector
	for i = 0,N do
	    v(i) = a
	end
	return v
    end
    return Class
end)

import "terratest" -- using the terra unit test library


testenv "Vector implementation" do
  
for _,T in pairs{int32,int64} do
  for N=2,3 do  

    --parameterized testset      
    testset(N,T) "fill" do
      local SVec = SVector(T,N)                      
      terradef                              
        var y = SVec.fill(3)
      end
      test y:size()==N
      for i=0,N-1 do          
        test y(i)==T(3)
      end
    end

  end
end

end --testenv

               
for _,T in pairs{int32,int64} do
  for N=2,3 do          
       
    --parameterized testenv        
    testenv(N,T) "Vector implementation" do
  
      --parameterized testset          
      testset "fill" do
        local SVec = SVector(T,N)                          
        terradef                                  
          var y = SVec.fill(3)
        end 
        test y:size()==N
        for i=0,N-1 do              
          test y(i)==T(3)
        end 
      end 
  
    end --testenv

  end --N
end --T 


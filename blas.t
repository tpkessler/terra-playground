local axpy = require("axpy")

local S = {}
for name, method in pairs(axpy) do
    if S.name ~= nil then
        next
    else
        S.name = method
    end
end

return S

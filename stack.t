local concept = require("concept")

local Stack = concept.AbstractInterface:new("Stack", {
  size = {} -> concept.UInteger,
  get = concept.UInteger -> concept.Number,
  set = {concept.UInteger, concept.Number} -> {},
})

return {
    Stack = Stack,
}


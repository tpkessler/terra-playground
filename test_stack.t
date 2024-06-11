import "terratest/terratest"

local concept = require("concept")
local stack = require("stack")

testenv "Stack" do
	testset "Stacker interface" do
		local StackerDouble = stack.Stacker(double)
		test [StackerDouble.isimplemented ~= nil]
	end

	testset "Stack concept" do
		local StackConcept = stack.Stack(double)
		test [concept.isconcept(StackConcept)]
	end

	testset "Dynamic Stack" do
		local DynStack = stack.DynamicStack(double)
		local StackConcept = stack.Stack(double)
		test [StackConcept(DynStack)]
		test [StackConcept(double[4]) == false]
	end

end

terra foo :: double -> double
terra bar :: double -> double
terra wro :: double -> int

print(foo.type == wro.type)
print(foo.type)

struct bar{
	x: double
	y: &int
}
terra bar:foo()
	self.x = 2.0 * @self.y
end

print("Entries")
for k, v in pairs(bar:getentries()) do
	print(k, v, v.field, v.type)
end

for k, v in pairs(bar.methods) do
	print(k, v)
end

for k, v in pairs(bar.entries) do
	-- print(k, v)
	for kk, vv in pairs(v) do
		-- print(kk, vv)
	end
end

for k, v in pairs(bar) do
	-- print(k, v)
end

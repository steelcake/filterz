fuzz:
	zig build test --fuzz --port 1337 -Doptimize=ReleaseSafe
benchmark:
	zig build runbench -Doptimize=ReleaseSafe -- 354881A65cBBd912560105DeF0bc5a2830822ECA 202bB2FaB1e35D940FdE99b214Ba49DAfbCef62A 00FC00900000002C00BE4EF8F49c000211000c43

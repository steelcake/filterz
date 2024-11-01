fuzz:
	zig build test --fuzz --port 1337 -Doptimize=ReleaseSafe

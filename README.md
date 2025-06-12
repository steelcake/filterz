# filterz

Implementations of some probabilistic filter structures. Implemented with `build once, use many times` use case in mind.
All filters export a `Filter` interface that can be used like this:

> [!WARNING]
> Using xor/ribbon filters with weird sized integers like u7, u6 etc. doesn't work properly. Need to implement manual integer bit packed slices for it to properly work.
> It is recommended to just use ribbon filter with u8 or u16

```zig
const Filter = filterz.ribbon.Filter(u10);

var my_filter = try Filter.init(alloc, hashes);
defer my_filter.deinit();

for (hashes) |h| {
  try std.testing.expect(filter.check(h));
} 
```

Each filter also exports a lower level API that can be used to implement more advanced use cases like:
- Reducing bits-per-key while the program is running to meet some memory usage criteria.
- Loading only a part of a filter from disk and using it to query.

Developed with latest zig release (master branch).
It means it hasn't been updated properly yet if it doesn't work with current master release.

## Filters

### Split-Block-Bloom-Filter

Speed optimized version of a bloom filter.

As described in https://github.com/apache/parquet-format/blob/master/BloomFilter.md

### Xor (BinaryFuse) filter

As described in https://arxiv.org/abs/2201.01174
Construction is a bit janky but constructed filters reach slightly higher space efficiency. This is better in cases where construction is one time and the filter is used for a much longer time.

### Ribbon filter 

As described in https://arxiv.org/abs/2103.02515

The implementation corresponds to the standard ribbon filter with "smash" as described in the paper.

## Benchmarks

1. Download Benchmark Data - instructions [here](bench-data/README.md)
2. Run benchmarks with:
```bash
make benchmark
```

[Example results](./bench_result_low_hit.txt)

NOTE: Cost estimate stat in the benchmark output is calculated by assuming every hit generates a disk read, which is priced at 200 microseconds.

Ribbon filter seems to be the best option when on a memory budget. Bloom filter is the king when there is no memory budget.

### TODO

- Implement [frayed ribbon based filter](https://github.com/bitwiseshiftleft/compressed_map)
- Implement [bumped ribbon filter](https://github.com/lorenzhs/BuRR)
- Implement interleaved columnar storage for ribbon filter as described in the paper.
- Implement mixing column sizes in ribbon filter storage to support fractional bits-per-key configurations e.g. 6.6 bits per key instead of 6 or 7.
- Improve Xor (Binary Fuse) filter construction speed by pre-sorting the hashes before filter construction as described in the paper.
- Improve Xor filter parameter selection, currently it is done by trial-error at construction time.

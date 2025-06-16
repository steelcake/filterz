# filterz

Implementations of some probabilistic filter structures. Implemented with `build once, use many times` use case in mind.
All filters export a `Filter` interface that can be used like this:

```zig
const Filter = filterz.xorf.Filter(u16);

var my_filter = try Filter.init(alloc, hashes);
defer my_filter.deinit();

for (hashes) |h| {
  try std.testing.expect(filter.check(h));
} 
```

This interface is mainly intended for testing, the lower level APIs exported from filter files are intended for production use.

> [!WARNING]
> Using xor/ribbon filters with weird sized integers like u7, u6 etc. doesn't work properly. Need to implement manual integer bit packed slices for it to properly work.

> [!WARNING]
> Developed with latest zig release (master branch).
It means it hasn't been updated properly yet if it doesn't work with current master release.

## Filters

### Split-Block-Bloom-Filter

Speed optimized version of a bloom filter.

As described in https://github.com/apache/parquet-format/blob/master/BloomFilter.md

### Xor (BinaryFuse) filter

As described in https://arxiv.org/abs/2201.01174

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

## License

Licensed under either of

 * Apache License, Version 2.0
   ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license
   ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.


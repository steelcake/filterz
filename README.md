# filterz

Implementations of some probabilistic filter structures. Implemented with `build once, use many times` use case in mind.
All filters export a `Filter` interface that can be used like this:

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

Requires Zig 0.14.0-dev release.

## Filters

### Split-Block-Bloom-Filter

As described in https://github.com/apache/parquet-format/blob/master/BloomFilter.md

### Xor (BinaryFuse) filter

Mostly as described in https://arxiv.org/abs/2201.01174
Construction can be improved as described in `Some things that can be improved` section.

### Ribbon filter 

As described in https://arxiv.org/abs/2103.02515
Solution matrix layout can be improved as described in `Some things that can be improved` section.
Also a nicer api for dynamic `bits-per-key` would be nice so user can lower bits-per-key while the program is running to control memory usage.

## Benchmarks

1. Download Benchmark Data - instructions [here](bench-data/README.md)
2. Run benchmarks with:
```bash
make benchmark
```

[Example results](./bench_result_low_hit.txt)

NOTE: Cost estimate stat in the benchmark output is calculated by assuming every hit generates a disk read, which is priced at 200 microseconds.

Ribbon filter seems to be the best option when on a memory budget. Bloom filter is the king when there is no memory budget.

### Some things that can be improved

Xor filter implemented here is really a BinaryFuse filter. The construction is pretty sketchy but it tries to optimize false positive rate and construction success over construction time.
I initially implemented it same as in the original C/C++ implementations but it was failing construction, this might be due to some errors in my implementation. Also some optimizations for construction are not implemented. It would be nice to work on these.
I am leaving it like this since the space-efficiency/false-positive-rate/query-time roughly meet the numbers given in the paper and it seems like ribbon filter is the better option.

Ribbon filter uses a row-major layout with some vectorization in query. The paper says this is not the best and interleaved-column-major layout with column sizes is the best. I didn't implement this initially because it is more difficult.
Seems like a vanilla implementation in zig goes a long way since we can use the filter with fingerprint types like `u10`. It would be nice to explore implementing interleaved-column-major layout as described in the paper. Or at least supporting mixed column sizes
 to support fractional bits-per-key values would be nice to meet memory budgets more tightly.

There are some ideas that improve the split block bloom filter but they don't drastically effect space efficiency which is what the implementations here are trying to optimize. Seems like these improvements are intended to make false positive rates more stable.
Rocksdb has a very nicely commented implementation of this.

Would be nice to have a structure that mixes the bloom retrieval and filtering so we have something that says the key is in the set and also gives a value that corresponds to the key. This can be very effective in cases like databases if we are skipping over sections with x elements and each section has x/y sub-sections inside.
Then our query can say, yes your query should visit this section and it should visit subsections 0,2 and 5 instead of just saying it should visit the section.

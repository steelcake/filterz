# Bench Data Generator

This script downloads Ethereum transaction data for benchmarking various filter implementations.

## Setup (not-uv)

1. Create a Python virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Usage with uv

```bash
uv run bench_data.py
```

## Usage

Run the data collection script:
```bash
python bench_data.py
```

This will generate two files:
- `addr.data`: Raw address data
- `addr.index`: Index file containing address counts per section

## Configuration

The script is configured by default to:
- Download ~50 million transactions
- Process them in sections of 1,000,000 transactions
- Start from block 16123123

This will create a 2GB file on disk and the benchmark runner loads the entire file to memory.
This might cause OOM failure if the system doesn't have enough RAM.

You can modify these parameters in the script by adjusting:
- `TOTAL_TX`: Total number of transactions to process
- `TX_PER_SECTION`: Number of transactions per section
- `query.from_block`: The block to start downloading from

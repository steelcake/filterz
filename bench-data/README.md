# Bench Data Generator

This script downloads Ethereum transaction data for benchmarking various filter implementations.

## Setup

1. Create a Python virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
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
- Download 10 million transactions
- Process them in sections of 100,000 transactions
- Start from block 18123123

You can modify these parameters in the script by adjusting:
- `TOTAL_TX`: Total number of transactions to process
- `TX_PER_SECTION`: Number of transactions per section

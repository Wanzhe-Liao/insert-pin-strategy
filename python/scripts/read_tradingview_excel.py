#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Read TradingView Excel export and analyze the data
"""

import sys

try:
    import pandas as pd
    print("pandas imported successfully")
except ImportError:
    print("ERROR: pandas not available")
    sys.exit(1)

# Try to read Excel file
excel_file = r'C:\Users\ROG\Downloads\三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx'

print(f"Attempting to read: {excel_file}")

try:
    # Try with openpyxl engine first
    df = pd.read_excel(excel_file, engine='openpyxl')
    print("Successfully read with openpyxl engine")
except Exception as e1:
    print(f"openpyxl failed: {e1}")
    try:
        # Try with xlrd engine
        df = pd.read_excel(excel_file, engine='xlrd')
        print("Successfully read with xlrd engine")
    except Exception as e2:
        print(f"xlrd failed: {e2}")
        try:
            # Try without specifying engine
            df = pd.read_excel(excel_file)
            print("Successfully read without specifying engine")
        except Exception as e3:
            print(f"Default engine failed: {e3}")
            print("\nTrying to read all available sheets...")
            try:
                xl_file = pd.ExcelFile(excel_file)
                print(f"Available sheets: {xl_file.sheet_names}")
                df = pd.read_excel(xl_file, sheet_name=xl_file.sheet_names[0])
                print(f"Successfully read first sheet: {xl_file.sheet_names[0]}")
            except Exception as e4:
                print(f"All methods failed: {e4}")
                sys.exit(1)

print(f"\nDataFrame loaded successfully!")
print(f"Shape: {df.shape}")
print(f"\nColumn names:")
for i, col in enumerate(df.columns):
    print(f"  {i}: {col}")

print(f"\nFirst 10 rows:")
print(df.head(10))

print(f"\nLast 5 rows:")
print(df.tail(5))

print(f"\nData types:")
print(df.dtypes)

print(f"\nBasic statistics:")
print(df.describe())

# Save to CSV for easier inspection
output_csv = r'data/tradingview_results.csv'
df.to_csv(output_csv, index=False, encoding='utf-8-sig')
print(f"\nSaved to: {output_csv}")

# Also save detailed info
output_info = r'docs/reports/tradingview_info.txt'
with open(output_info, 'w', encoding='utf-8') as f:
    f.write(f"TradingView Results Analysis\n")
    f.write(f"="*80 + "\n\n")
    f.write(f"Shape: {df.shape}\n")
    f.write(f"Rows: {len(df)}\n")
    f.write(f"Columns: {len(df.columns)}\n\n")
    f.write(f"Column names:\n")
    for i, col in enumerate(df.columns):
        f.write(f"  {i}: {col}\n")
    f.write(f"\n")
    f.write(f"Data types:\n{df.dtypes}\n\n")
    f.write(f"First 20 rows:\n{df.head(20)}\n\n")
    f.write(f"Basic statistics:\n{df.describe()}\n")

print(f"Saved detailed info to: {output_info}")

#!/usr/bin/env Rscript
# Read TradingView Excel export and analyze the data

library(readxl)
library(dplyr)
library(lubridate)

# Read Excel file
excel_file <- "C:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx"

cat("Reading Excel file:", excel_file, "\n")

# Get sheet names
sheet_names <- excel_sheets(excel_file)
cat("Available sheets:", paste(sheet_names, collapse=", "), "\n\n")

# Read first sheet
df <- read_excel(excel_file, sheet = sheet_names[1])

cat("Data loaded successfully!\n")
cat("Dimensions:", nrow(df), "rows x", ncol(df), "columns\n\n")

cat("Column names:\n")
for(i in 1:ncol(df)) {
  cat(sprintf("  %d: %s\n", i, colnames(df)[i]))
}

cat("\nFirst 10 rows:\n")
print(head(df, 10))

cat("\nLast 5 rows:\n")
print(tail(df, 5))

cat("\nData structure:\n")
str(df)

cat("\nSummary statistics:\n")
print(summary(df))

# Save to CSV
output_csv <- "data/tradingview_results.csv"
write.csv(df, output_csv, row.names = FALSE, fileEncoding = "UTF-8")
cat("\nSaved to CSV:", output_csv, "\n")

# Save detailed info
output_info <- "docs/reports/tradingview_info.txt"
sink(output_info)
cat("TradingView Results Analysis\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")
cat("Shape:", nrow(df), "rows x", ncol(df), "columns\n\n")
cat("Column names:\n")
for(i in 1:ncol(df)) {
  cat(sprintf("  %d: %s\n", i, colnames(df)[i]))
}
cat("\nData structure:\n")
str(df)
cat("\nFirst 20 rows:\n")
print(head(df, 20))
cat("\nSummary statistics:\n")
print(summary(df))
sink()

cat("Saved detailed info to:", output_info, "\n")

# Try to extract key metrics if available
cat("\n" , paste(rep("=", 80), collapse=""), "\n")
cat("EXTRACTING KEY METRICS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Look for performance summary columns
possible_metric_cols <- c("Net Profit", "Total Trades", "Percent Profitable",
                          "Max Drawdown", "Return", "Win Rate", "Total Closed Trades",
                          "Profit Factor", "Sharpe Ratio")

for(col in possible_metric_cols) {
  if(col %in% colnames(df)) {
    cat(sprintf("%s: %s\n", col, df[[col]][1]))
  }
}

# Check if this is a trade list
if("Entry Time" %in% colnames(df) || "Exit Time" %in% colnames(df)) {
  cat("\nThis appears to be a TRADE LIST\n")
  cat("Number of trades:", nrow(df), "\n")

  # Show first 20 trades
  cat("\nFirst 20 trades:\n")
  print(head(df, 20))
}

cat("\nDone!\n")

#!/usr/bin/env Rscript
# Read TradingView trade list from Excel

library(readxl)
library(dplyr)
library(lubridate)

# Read Excel file
excel_file <- "C:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx"

cat("Reading Excel file:", excel_file, "\n\n")

# Read all sheets
cat("=" , paste(rep("=", 80), collapse=""), "\n")
cat("SHEET 1: Performance Summary (表现)\n")
cat(paste(rep("=", 80), collapse=""), "\n")
performance <- read_excel(excel_file, sheet = "表现")
print(performance)

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("SHEET 2: Trade Analysis (交易分析)\n")
cat(paste(rep("=", 80), collapse=""), "\n")
trade_analysis <- read_excel(excel_file, sheet = "交易分析")
print(trade_analysis)

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("SHEET 3: Risk Metrics (风险 表现比)\n")
cat(paste(rep("=", 80), collapse=""), "\n")
risk_metrics <- read_excel(excel_file, sheet = "风险 表现比")
print(risk_metrics)

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("SHEET 4: Trade List (交易清单) - MOST IMPORTANT\n")
cat(paste(rep("=", 80), collapse=""), "\n")
trade_list <- read_excel(excel_file, sheet = "交易清单")
cat("Number of trades:", nrow(trade_list), "\n")
cat("Columns:", paste(colnames(trade_list), collapse=", "), "\n\n")

cat("First 20 trades:\n")
print(head(trade_list, 20))

cat("\n\nLast 10 trades:\n")
print(tail(trade_list, 10))

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("SHEET 5: Properties (属性)\n")
cat(paste(rep("=", 80), collapse=""), "\n")
properties <- read_excel(excel_file, sheet = "属性")
print(properties)

# Save trade list to CSV
output_csv <- "data/tradingview_trades.csv"
write.csv(trade_list, output_csv, row.names = FALSE, fileEncoding = "UTF-8")
cat("\n\nSaved trade list to:", output_csv, "\n")

# Extract key metrics from performance sheet
cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("KEY METRICS SUMMARY\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Extract from performance sheet
perf_df <- as.data.frame(performance)
for(i in 1:nrow(perf_df)) {
  metric_name <- perf_df[i, 1]
  metric_value_usdt <- perf_df[i, 2]
  metric_value_pct <- perf_df[i, 3]

  cat(sprintf("%-25s: %12.2f USDT", metric_name, metric_value_usdt))
  if(!is.na(metric_value_pct)) {
    cat(sprintf(" (%8.2f%%)", metric_value_pct))
  }
  cat("\n")
}

# Extract from trade analysis
cat("\n")
if(nrow(trade_analysis) > 0) {
  trade_df <- as.data.frame(trade_analysis)
  for(i in 1:nrow(trade_df)) {
    metric_name <- trade_df[i, 1]
    metric_value <- trade_df[i, 2]
    cat(sprintf("%-25s: %s\n", metric_name, metric_value))
  }
}

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("TRADE LIST ANALYSIS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

if(nrow(trade_list) > 0) {
  cat("Total trades:", nrow(trade_list), "\n")

  # Calculate statistics if profit column exists
  if("Profit" %in% colnames(trade_list)) {
    profit_col <- trade_list$Profit
    winning_trades <- sum(profit_col > 0, na.rm = TRUE)
    losing_trades <- sum(profit_col < 0, na.rm = TRUE)
    breakeven_trades <- sum(profit_col == 0, na.rm = TRUE)

    cat("Winning trades:", winning_trades, "\n")
    cat("Losing trades:", losing_trades, "\n")
    cat("Breakeven trades:", breakeven_trades, "\n")
    cat("Win rate:", sprintf("%.2f%%", 100 * winning_trades / (winning_trades + losing_trades)), "\n")
    cat("Total profit:", sum(profit_col, na.rm = TRUE), "\n")
    cat("Average profit:", mean(profit_col, na.rm = TRUE), "\n")
    cat("Max profit:", max(profit_col, na.rm = TRUE), "\n")
    cat("Max loss:", min(profit_col, na.rm = TRUE), "\n")
  }
}

cat("\nDone!\n")

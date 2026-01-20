#!/usr/bin/env Rscript
# Run R backtest with exact same parameters as TradingView and save detailed trade log

library(xts)
library(data.table)
library(RcppRoll)

# Source the backtest engine
source("backtest_final_fixed.R")

# Load data
cat("Loading PEPEUSDT data...\n")
data_file <- "data/PEPEUSDT_15m.rds"

if (!file.exists(data_file)) {
  stop("Data file not found: ", data_file)
}

xts_data <- readRDS(data_file)
cat("Data loaded:", nrow(xts_data), "bars\n")
cat("Date range:", format(start(xts_data)), "to", format(end(xts_data)), "\n\n")

# Run backtest with exact parameters
cat("Running backtest with parameters:\n")
cat("  Lookback: 3 days\n")
cat("  Drop threshold: 20%\n")
cat("  Take profit: 10%\n")
cat("  Stop loss: 10%\n")
cat("  Initial capital: 10000 USDT\n")
cat("  Fee rate: 0.075%\n\n")

start_time <- Sys.time()

result <- backtest_drop_strategy_fixed(
  data = xts_data,
  lookback_days = 3,
  drop_threshold = 20,
  take_profit = 10,
  stop_loss = 10,
  initial_capital = 10000,
  fee_rate = 0.075,
  verbose = TRUE
)

end_time <- Sys.time()
execution_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n", paste(rep("=", 80), collapse=""), "\n")
cat("BACKTEST RESULTS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

cat(sprintf("Execution time: %.3f seconds\n\n", execution_time))

cat("Overall Metrics:\n")
cat(sprintf("  Total signals: %d\n", result$signals))
cat(sprintf("  Total trades: %d\n", result$trades))
cat(sprintf("  Final capital: %.2f USDT\n", result$final_capital))
cat(sprintf("  Return: %.2f%%\n", result$return_pct))
cat(sprintf("  Win rate: %.2f%%\n", result$win_rate))
cat(sprintf("  Max drawdown: %.2f%%\n", result$max_drawdown))
cat(sprintf("  Total fees: %.2f USDT\n", result$total_fees))

# Save trade log to CSV
if (!is.null(result$trade_log) && nrow(result$trade_log) > 0) {
  cat("\n", paste(rep("=", 80), collapse=""), "\n")
  cat("TRADE LOG\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n")

  trade_log <- result$trade_log

  # Add Excel date/time format (days since 1900-01-01)
  excel_epoch <- as.POSIXct("1899-12-30 00:00:00", tz = "UTC")
  trade_log$entry_excel_date <- as.numeric(difftime(trade_log$entry_time, excel_epoch, units = "days"))
  trade_log$exit_excel_date <- as.numeric(difftime(trade_log$exit_time, excel_epoch, units = "days"))

  # Show first 20 trades
  cat("First 20 trades:\n")
  print(head(trade_log, 20))

  # Save to CSV
  output_csv <- "r_backtest_trades.csv"
  write.csv(trade_log, output_csv, row.names = FALSE, fileEncoding = "UTF-8")
  cat("\nTrade log saved to:", output_csv, "\n")

  # Create detailed comparison format
  cat("\n", paste(rep("=", 80), collapse=""), "\n")
  cat("DETAILED TRADE COMPARISON FORMAT\n")
  cat(paste(rep("=", 80), collapse=""), "\n\n")

  for(i in 1:min(20, nrow(trade_log))) {
    trade <- trade_log[i, ]
    cat(sprintf("\nTrade #%d:\n", trade$trade_id))
    cat(sprintf("  Entry:\n"))
    cat(sprintf("    Bar: %d\n", trade$entry_bar))
    cat(sprintf("    Time: %s\n", format(trade$entry_time, "%Y-%m-%d %H:%M:%S")))
    cat(sprintf("    Excel Time: %.10f\n", trade$entry_excel_date))
    cat(sprintf("    Price: %.10f USDT\n", trade$entry_price))
    cat(sprintf("    Position Size: %.2f USDT\n", trade$position_size_value))
    cat(sprintf("    Shares: %.0f\n", trade$position_size_shares))
    cat(sprintf("    Capital Before: %.2f USDT\n", trade$capital_before))
    cat(sprintf("  Exit:\n"))
    cat(sprintf("    Bar: %d\n", trade$exit_bar))
    cat(sprintf("    Time: %s\n", format(trade$exit_time, "%Y-%m-%d %H:%M:%S")))
    cat(sprintf("    Excel Time: %.10f\n", trade$exit_excel_date))
    cat(sprintf("    Price: %.10f USDT\n", trade$exit_price))
    cat(sprintf("    Reason: %s\n", trade$exit_reason))
    cat(sprintf("  Performance:\n"))
    cat(sprintf("    Net PnL: %.2f USDT (%.2f%%)\n", trade$net_pnl, trade$net_pnl_pct))
    cat(sprintf("    Entry Fee: %.2f USDT\n", trade$entry_fee))
    cat(sprintf("    Exit Fee: %.2f USDT\n", trade$exit_fee))
    cat(sprintf("    Total Fee: %.2f USDT\n", trade$total_fee))
    cat(sprintf("    Capital After: %.2f USDT\n", trade$capital_after))
    cat(sprintf("    Cumulative Return: %.2f%%\n", trade$cumulative_return_pct))
  }
}

cat("\nDone!\n")

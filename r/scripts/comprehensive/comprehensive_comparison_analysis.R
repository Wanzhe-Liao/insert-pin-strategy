#!/usr/bin/env Rscript
# Comprehensive comparison between TradingView and R backtest results

library(readxl)
library(dplyr)
library(lubridate)

cat("\n")
cat(paste(rep("=", 100), collapse=""), "\n")
cat("                        TRADINGVIEW vs R BACKTEST COMPARISON ANALYSIS\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

# ============================================================================
# PART 1: Load TradingView Results
# ============================================================================

cat("PART 1: Loading TradingView Results\n")
cat(paste(rep("-", 100), collapse=""), "\n\n")

tv_file <- "C:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx"

# Load performance metrics
tv_performance <- read_excel(tv_file, sheet = "表现")
cat("TradingView Performance Metrics:\n")
print(tv_performance)

# Load trade analysis
tv_trade_analysis <- read_excel(tv_file, sheet = "交易分析")
cat("\nTradingView Trade Analysis:\n")
print(tv_trade_analysis)

# Load trade list
tv_trades <- read_excel(tv_file, sheet = "交易清单")
cat("\nTradingView Trade List:\n")
cat("  Total rows:", nrow(tv_trades), "\n")
cat("  Columns:", paste(colnames(tv_trades), collapse=", "), "\n\n")

# Load properties
tv_properties <- read_excel(tv_file, sheet = "属性")
cat("TradingView Properties:\n")
print(tv_properties)

# ============================================================================
# PART 2: Load R Backtest Results
# ============================================================================

cat("\n\n")
cat("PART 2: Loading R Backtest Results\n")
cat(paste(rep("-", 100), collapse=""), "\n\n")

r_trades <- read.csv("outputs/detailed_trades_comparison.csv", stringsAsFactors = FALSE)

cat("R Backtest Trade List:\n")
cat("  Total rows:", nrow(r_trades), "\n")
cat("  Columns:", paste(colnames(r_trades), collapse=", "), "\n\n")

# Convert time columns
r_trades$Entry_Time <- as.POSIXct(r_trades$Entry_Time, tz = "UTC")
r_trades$Exit_Time <- as.POSIXct(r_trades$Exit_Time, tz = "UTC")

# Calculate R backtest metrics
r_metrics <- list(
  total_trades = nrow(r_trades),
  winning_trades = sum(r_trades$PnL_Percent > 0),
  losing_trades = sum(r_trades$PnL_Percent < 0),
  win_rate = 100 * sum(r_trades$PnL_Percent > 0) / nrow(r_trades),
  avg_pnl_pct = mean(r_trades$PnL_Percent),
  max_win = max(r_trades$PnL_Percent),
  max_loss = min(r_trades$PnL_Percent)
)

cat("R Backtest Metrics:\n")
for(name in names(r_metrics)) {
  cat(sprintf("  %s: %.2f\n", name, r_metrics[[name]]))
}

# ============================================================================
# PART 3: Extract TradingView Key Metrics
# ============================================================================

cat("\n\n")
cat("PART 3: Extracting TradingView Key Metrics\n")
cat(paste(rep("-", 100), collapse=""), "\n\n")

# Extract from performance sheet
tv_net_profit <- tv_performance[[2]][tv_performance[[1]] == "净利润"]
tv_net_profit_pct <- tv_performance[[3]][tv_performance[[1]] == "净利润"]
tv_max_drawdown <- tv_performance[[2]][tv_performance[[1]] == "最大股权回撤"]
tv_max_drawdown_pct <- tv_performance[[3]][tv_performance[[1]] == "最大股权回撤"]
tv_fees <- tv_performance[[2]][tv_performance[[1]] == "已支付佣金"]

# Extract from trade analysis
tv_total_trades <- tv_trade_analysis[[2]][tv_trade_analysis[[1]] == "总交易"]
tv_winning_trades <- tv_trade_analysis[[2]][tv_trade_analysis[[1]] == "盈利交易"]
tv_losing_trades <- tv_trade_analysis[[2]][tv_trade_analysis[[1]] == "亏损交易"]
tv_win_rate <- tv_trade_analysis[[3]][tv_trade_analysis[[1]] == "获利百分比"]
tv_avg_pnl <- tv_trade_analysis[[2]][tv_trade_analysis[[1]] == "平均P&L"]
tv_avg_pnl_pct <- tv_trade_analysis[[3]][tv_trade_analysis[[1]] == "平均P&L"]

cat("TradingView Key Metrics Summary:\n")
cat(sprintf("  Net Profit: %.2f USDT (%.2f%%)\n", tv_net_profit, tv_net_profit_pct))
cat(sprintf("  Total Trades: %.0f\n", tv_total_trades))
cat(sprintf("  Winning Trades: %.0f\n", tv_winning_trades))
cat(sprintf("  Losing Trades: %.0f\n", tv_losing_trades))
cat(sprintf("  Win Rate: %.2f%%\n", tv_win_rate))
cat(sprintf("  Avg PnL: %.2f USDT (%.2f%%)\n", tv_avg_pnl, tv_avg_pnl_pct))
cat(sprintf("  Max Drawdown: %.2f USDT (%.2f%%)\n", tv_max_drawdown, tv_max_drawdown_pct))
cat(sprintf("  Total Fees: %.2f USDT\n", tv_fees))

# ============================================================================
# PART 4: Side-by-Side Comparison
# ============================================================================

cat("\n\n")
cat("PART 4: Side-by-Side Metrics Comparison\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

comparison <- data.frame(
  Metric = c(
    "Net Profit (USDT)",
    "Net Profit (%)",
    "Total Trades",
    "Winning Trades",
    "Losing Trades",
    "Win Rate (%)",
    "Avg PnL per Trade (%)",
    "Max Drawdown (%)",
    "Total Fees (USDT)"
  ),
  TradingView = c(
    sprintf("%.2f", tv_net_profit),
    sprintf("%.2f", tv_net_profit_pct),
    sprintf("%.0f", tv_total_trades),
    sprintf("%.0f", tv_winning_trades),
    sprintf("%.0f", tv_losing_trades),
    sprintf("%.2f", tv_win_rate),
    sprintf("%.2f", tv_avg_pnl_pct),
    sprintf("%.2f", tv_max_drawdown_pct),
    sprintf("%.2f", tv_fees)
  ),
  R_Backtest = c(
    "N/A (need final capital)",
    "318.56",
    sprintf("%.0f", nrow(r_trades)),
    sprintf("%.0f", r_metrics$winning_trades),
    sprintf("%.0f", r_metrics$losing_trades),
    sprintf("%.2f", r_metrics$win_rate),
    sprintf("%.2f", r_metrics$avg_pnl_pct),
    "56.95",
    "7279.81"
  ),
  stringsAsFactors = FALSE
)

print(comparison)

# Calculate differences
cat("\n\nKEY DIFFERENCES:\n")
cat(sprintf("  Trade Count: TradingView has %.0f trades, R has %.0f trades (difference: %.0f)\n",
            tv_total_trades, nrow(r_trades), nrow(r_trades) - tv_total_trades))
cat(sprintf("  Win Rate: TradingView %.2f%%, R %.2f%% (difference: %.2f%%)\n",
            tv_win_rate, r_metrics$win_rate, r_metrics$win_rate - tv_win_rate))
cat(sprintf("  Return: TradingView %.2f%%, R 318.56%% (difference: %.2f%%)\n",
            tv_net_profit_pct, tv_net_profit_pct - 318.56))

# ============================================================================
# PART 5: Trade-by-Trade Comparison
# ============================================================================

cat("\n\n")
cat("PART 5: Trade-by-Trade Comparison (First 20 Trades)\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

# Process TradingView trades
# Note: TV trade list has 2 rows per trade (entry and exit)
tv_trades_processed <- data.frame()

for(i in seq(1, min(nrow(tv_trades), 40), by = 2)) {
  if(i + 1 > nrow(tv_trades)) break

  entry_row <- tv_trades[i + 1, ]  # Entry is the second row
  exit_row <- tv_trades[i, ]       # Exit is the first row

  trade <- data.frame(
    trade_no = exit_row[[1]],
    entry_excel_time = entry_row[[3]],
    entry_price = entry_row[[5]],
    exit_excel_time = exit_row[[3]],
    exit_price = exit_row[[5]],
    net_pnl_usdt = exit_row[[8]],
    net_pnl_pct = exit_row[[9]],
    exit_reason = exit_row[[4]],
    stringsAsFactors = FALSE
  )

  tv_trades_processed <- rbind(tv_trades_processed, trade)
}

# Convert Excel dates to timestamps
excel_epoch <- as.POSIXct("1899-12-30 00:00:00", tz = "UTC")
tv_trades_processed$entry_time <- excel_epoch + as.numeric(tv_trades_processed$entry_excel_time) * 86400
tv_trades_processed$exit_time <- excel_epoch + as.numeric(tv_trades_processed$exit_excel_time) * 86400

cat("TradingView - First 10 Completed Trades:\n\n")
for(i in 1:min(10, nrow(tv_trades_processed))) {
  trade <- tv_trades_processed[i, ]
  cat(sprintf("Trade #%d:\n", trade$trade_no))
  cat(sprintf("  Entry: %s @ %.10f USDT\n", format(trade$entry_time, "%Y-%m-%d %H:%M:%S"), trade$entry_price))
  cat(sprintf("  Exit:  %s @ %.10f USDT\n", format(trade$exit_time, "%Y-%m-%d %H:%M:%S"), trade$exit_price))
  cat(sprintf("  PnL: %.2f USDT (%.2f%%), Reason: %s\n", trade$net_pnl_usdt, trade$net_pnl_pct, trade$exit_reason))
  cat("\n")
}

cat("\n")
cat("R Backtest - First 10 Trades:\n\n")
for(i in 1:min(10, nrow(r_trades))) {
  trade <- r_trades[i, ]
  cat(sprintf("Trade #%d:\n", trade$Trade_No))
  cat(sprintf("  Entry: %s @ %.10f USDT\n", format(trade$Entry_Time, "%Y-%m-%d %H:%M:%S"), trade$Entry_Price))
  cat(sprintf("  Exit:  %s @ %.10f USDT\n", format(trade$Exit_Time, "%Y-%m-%d %H:%M:%S"), trade$Exit_Price))
  cat(sprintf("  PnL: %.2f%%, Reason: %s, Holding: %d bars\n", trade$PnL_Percent, trade$Exit_Type, trade$Holding_Bars))
  cat("\n")
}

# ============================================================================
# PART 6: Detailed Analysis of Differences
# ============================================================================

cat("\n\n")
cat("PART 6: Analysis of Differences\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

cat("IDENTIFIED DISCREPANCIES:\n\n")

cat("1. TRADE COUNT DIFFERENCE:\n")
cat(sprintf("   - TradingView: %.0f trades\n", tv_total_trades))
cat(sprintf("   - R Backtest: %d trades\n", nrow(r_trades)))
cat(sprintf("   - Difference: %d trades (%.1fx)\n", nrow(r_trades) - tv_total_trades, nrow(r_trades) / tv_total_trades))
cat("   - Possible Reasons:\n")
cat("     * Different signal generation logic\n")
cat("     * Different signal filtering\n")
cat("     * Different handling of consecutive signals\n\n")

cat("2. WIN RATE DIFFERENCE:\n")
cat(sprintf("   - TradingView: %.2f%% (%.0f wins / %.0f losses)\n", tv_win_rate, tv_winning_trades, tv_losing_trades))
cat(sprintf("   - R Backtest: %.2f%% (%d wins / %d losses)\n", r_metrics$win_rate, r_metrics$winning_trades, r_metrics$losing_trades))
cat(sprintf("   - Difference: %.2f%%\n", r_metrics$win_rate - tv_win_rate))
cat("   - Possible Reasons:\n")
cat("     * Different stop loss/take profit trigger logic\n")
cat("     * Different price used for exit (close vs intrabar)\n\n")

cat("3. RETURN DIFFERENCE:\n")
cat(sprintf("   - TradingView: %.2f%%\n", tv_net_profit_pct))
cat("   - R Backtest: 318.56%\n")
cat(sprintf("   - Difference: %.2f%%\n", 318.56 - tv_net_profit_pct))
cat("   - Possible Reasons:\n")
cat("     * Different compounding methodology\n")
cat("     * Different position sizing\n")
cat("     * More trades = more compound growth\n\n")

cat("4. FIRST TRADE COMPARISON:\n\n")
if(nrow(tv_trades_processed) > 0 && nrow(r_trades) > 0) {
  tv_first <- tv_trades_processed[1, ]
  r_first <- r_trades[1, ]

  cat("   TradingView First Trade:\n")
  cat(sprintf("     Entry: %s @ %.10f USDT\n", format(tv_first$entry_time, "%Y-%m-%d %H:%M:%S"), tv_first$entry_price))
  cat(sprintf("     Exit:  %s @ %.10f USDT\n", format(tv_first$exit_time, "%Y-%m-%d %H:%M:%S"), tv_first$exit_price))
  cat(sprintf("     PnL: %.2f%%\n\n", tv_first$net_pnl_pct))

  cat("   R Backtest First Trade:\n")
  cat(sprintf("     Entry: %s @ %.10f USDT\n", format(r_first$Entry_Time, "%Y-%m-%d %H:%M:%S"), r_first$Entry_Price))
  cat(sprintf("     Exit:  %s @ %.10f USDT\n", format(r_first$Exit_Time, "%Y-%m-%d %H:%M:%S"), r_first$Exit_Price))
  cat(sprintf("     PnL: %.2f%%\n\n", r_first$PnL_Percent))

  # Check if they match
  time_diff <- abs(difftime(tv_first$entry_time, r_first$Entry_Time, units = "mins"))
  price_diff_pct <- abs(tv_first$entry_price - r_first$Entry_Price) / r_first$Entry_Price * 100

  cat("   Comparison:\n")
  cat(sprintf("     Entry Time Difference: %.0f minutes\n", time_diff))
  cat(sprintf("     Entry Price Difference: %.4f%%\n", price_diff_pct))

  if(time_diff < 60 && price_diff_pct < 1) {
    cat("     OK First trades are SIMILAR - good baseline alignment\n\n")
  } else {
    cat("     FAIL First trades are DIFFERENT - fundamental logic mismatch\n\n")
  }
}

# ============================================================================
# PART 7: Summary and Recommendations
# ============================================================================

cat("\n\n")
cat("PART 7: Summary and Recommendations\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

cat("SUMMARY OF FINDINGS:\n\n")

cat("1. Major Discrepancy in Trade Count:\n")
cat(sprintf("   - R generates %.1fx more trades than TradingView\n", nrow(r_trades) / tv_total_trades))
cat("   - This is the PRIMARY source of difference\n\n")

cat("2. Different Win Rate:\n")
cat(sprintf("   - TradingView: %.2f%% (all wins!)\n", tv_win_rate))
cat(sprintf("   - R Backtest: %.2f%%\n", r_metrics$win_rate))
cat("   - TradingView shows 100% win rate, which is suspicious\n\n")

cat("3. Vastly Different Returns:\n")
cat(sprintf("   - TradingView: %.2f%%\n", tv_net_profit_pct))
cat("   - R Backtest: 318.56%\n")
cat("   - Difference is driven by both trade count and compounding\n\n")

cat("ROOT CAUSE HYPOTHESES (ranked by likelihood):\n\n")

cat("1. ★★★★★ Signal Generation Timing:\n")
cat("   - TradingView may use 'close' of signal bar for entry\n")
cat("   - R may use 'open' of next bar after signal\n")
cat("   - This could cause many signals to be filtered out in TV\n\n")

cat("2. ★★★★☆ Position Management:\n")
cat("   - TradingView may not allow overlapping positions\n")
cat("   - R may allow multiple concurrent positions\n")
cat("   - Or one system filters signals during open positions\n\n")

cat("3. ★★★☆☆ Stop Loss/Take Profit Logic:\n")
cat("   - TradingView uses intrabar execution (actual high/low)\n")
cat("   - R may only check at bar close\n")
cat("   - This affects exit timing and prices\n\n")

cat("4. ★★☆☆☆ Fee Calculation:\n")
cat("   - Different fee application methods\n")
cat(sprintf("   - TradingView fees: %.2f USDT\n", tv_fees))
cat("   - R Backtest fees: 7279.81 USDT\n")
cat("   - Huge difference suggests different position sizing\n\n")

cat("RECOMMENDATIONS:\n\n")

cat("1. IMMEDIATE ACTIONS:\n")
cat("   a) Review signal generation logic in both systems\n")
cat("   b) Check if R allows multiple concurrent positions\n")
cat("   c) Verify stop loss/take profit trigger mechanism\n")
cat("   d) Compare position sizing formulas\n\n")

cat("2. DEBUGGING STEPS:\n")
cat("   a) Create a signal log from TradingView (all generated signals)\n")
cat("   b) Create a signal log from R (all generated signals)\n")
cat("   c) Compare signal counts and timing\n")
cat("   d) Identify where signals diverge\n\n")

cat("3. CODE REVIEW PRIORITIES:\n")
cat("   a) Entry timing: bar close vs next bar open\n")
cat("   b) Position management: single vs multiple positions\n")
cat("   c) Exit logic: intrabar vs bar close\n")
cat("   d) Fee application: per-trade vs position-based\n\n")

# ============================================================================
# SAVE RESULTS
# ============================================================================

# Save comparison table
write.csv(comparison, "outputs/tv_vs_r_comparison.csv", row.names = FALSE)
write.csv(tv_trades_processed, "outputs/tv_trades_processed.csv", row.names = FALSE)

cat("\n")
cat("Results saved to:\n")
cat("  - tv_vs_r_comparison.csv\n")
cat("  - tv_trades_processed.csv\n")

cat("\n")
cat(paste(rep("=", 100), collapse=""), "\n")
cat("                                      ANALYSIS COMPLETE\n")
cat(paste(rep("=", 100), collapse=""), "\n\n")

# ============================================================================
# 交易对比: 原版R vs 修复版R vs TradingView
# ============================================================================

# 读取数据
r_original <- read.csv("outputs/r_backtest_trades_final.csv", stringsAsFactors = FALSE)
r_fixed <- read.csv("outputs/r_backtest_trades_fixed.csv", stringsAsFactors = FALSE)
tv <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)

cat("\n")
cat("============================================================\n")
cat("交易对比: 原版R (11笔) vs 修复版R (9笔) vs TV (9笔)\n")
cat("============================================================\n\n")

cat("原版R的11笔交易:\n")
cat("------------------------------------------------------------\n")
for (i in 1:nrow(r_original)) {
  trade <- r_original[i, ]
  # 标记被移除的交易
  removed <- if (i == 3 || i == 10) " FAIL [已移除]" else ""
  cat(sprintf("#%d: 入场=%s, 出场=%s%s\n",
              trade$TradeId, trade$EntryTime, trade$ExitTime, removed))
}

cat("\n")
cat("修复版R的9笔交易:\n")
cat("------------------------------------------------------------\n")
for (i in 1:nrow(r_fixed)) {
  trade <- r_fixed[i, ]
  cat(sprintf("#%d: 入场=%s, 出场=%s\n",
              trade$TradeId, trade$EntryTime, trade$ExitTime))
}

cat("\n")
cat("TradingView的9笔交易:\n")
cat("------------------------------------------------------------\n")
for (i in 1:nrow(tv)) {
  trade <- tv[i, ]
  cat(sprintf("#%d: 入场=%s, 出场=%s\n",
              trade$TradeId, trade$EntryTime, trade$ExitTime))
}

cat("\n")
cat("============================================================\n")
cat("被移除的交易详情\n")
cat("============================================================\n\n")

# 原版R交易#3
cat("原版R交易#3 (已移除):\n")
cat(sprintf("  入场: %s @ %s\n", r_original[3, "EntryTime"], r_original[3, "EntryPrice"]))
cat(sprintf("  出场: %s @ %s\n", r_original[3, "ExitTime"], r_original[3, "ExitPrice"]))
cat(sprintf("  原因: %s\n", r_original[3, "ExitReason"]))
cat(sprintf("  盈亏: %s%%\n", r_original[3, "PnLPercent"]))
cat("  移除原因: 在原版R交易#2出场的同一根K线入场\n\n")

# 原版R交易#10
cat("原版R交易#10 (已移除):\n")
cat(sprintf("  入场: %s @ %s\n", r_original[10, "EntryTime"], r_original[10, "EntryPrice"]))
cat(sprintf("  出场: %s @ %s\n", r_original[10, "ExitTime"], r_original[10, "ExitPrice"]))
cat(sprintf("  原因: %s\n", r_original[10, "ExitReason"]))
cat(sprintf("  盈亏: %s%%\n", r_original[10, "PnLPercent"]))
cat("  移除原因: 在原版R交易#9出场的同一根K线入场\n\n")

cat("============================================================\n")
cat("交易编号对应关系\n")
cat("============================================================\n\n")

mapping <- data.frame(
  原版R = c(1, 2, "3 FAIL", 4, 5, 6, 7, 8, 9, "10 FAIL", 11),
  修复版R = c(1, 2, "-", 3, 4, 5, 6, 7, 8, "-", 9),
  TradingView = c(1, 2, "-", 3, 4, 5, 6, 7, 8, "-", 9),
  入场时间 = c(
    "2023-05-06 02:44",
    "2023-08-18 05:44",
    "2023-08-18 05:59",
    "2023-11-10 00:14",
    "2024-01-03 20:14",
    "2024-03-06 03:59",
    "2024-04-13 02:44",
    "2024-04-14 04:14",
    "2025-10-11 05:29",
    "2025-10-11 05:44",
    "2025-10-11 06:14"
  ),
  stringsAsFactors = FALSE
)

print(mapping)

cat("\n")
cat("说明:\n")
cat("  - FAIL 表示该交易在修复版中被移除\n")
cat("  - '-' 表示该位置没有对应交易\n")
cat("  - 原版R交易#3和#10被移除后, 后续交易编号前移\n")
cat("\n")

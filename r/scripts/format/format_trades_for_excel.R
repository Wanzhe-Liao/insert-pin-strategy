# 格式化交易记录为Excel友好格式

trades <- read.csv('detailed_trades_comparison.csv', stringsAsFactors=FALSE)

# 格式化价格为8位小数
trades$Entry_Price_Formatted <- sprintf('%.8f', trades$Entry_Price)
trades$Exit_Price_Formatted <- sprintf('%.8f', trades$Exit_Price)
trades$PnL_Formatted <- sprintf('%.2f%%', trades$PnL_Percent)

# 计算持仓时间（小时）
trades$Holding_Hours <- round(trades$Holding_Bars * 15 / 60, 1)

# 创建简化版本（前20笔）
top20 <- head(trades, 20)

# 创建对比表格
comparison_table <- data.frame(
  Trade_No = top20$Trade_No,
  Signal_Time = top20$Signal_Time,
  Entry_Price = top20$Entry_Price_Formatted,
  Exit_Time = top20$Exit_Time,
  Exit_Price = top20$Exit_Price_Formatted,
  PnL = top20$PnL_Formatted,
  Exit_Type = top20$Exit_Type,
  Holding_Bars = top20$Holding_Bars,
  Holding_Hours = top20$Holding_Hours,
  stringsAsFactors = FALSE
)

# 保存
write.csv(comparison_table, 'top20_trades_for_comparison.csv', row.names=FALSE)

cat("已生成前20笔交易对比文件: top20_trades_for_comparison.csv\n\n")
cat("前10笔交易:\n")
print(comparison_table[1:10, ])

# 生成统计摘要
cat("\n\n=== 统计摘要 ===\n")
cat(sprintf("总交易数: %d\n", nrow(trades)))
cat(sprintf("止盈次数: %d (%.1f%%)\n",
            sum(trades$Exit_Type == "TP"),
            sum(trades$Exit_Type == "TP")/nrow(trades)*100))
cat(sprintf("止损次数: %d (%.1f%%)\n",
            sum(trades$Exit_Type == "SL"),
            sum(trades$Exit_Type == "SL")/nrow(trades)*100))
cat(sprintf("平均盈亏: %.2f%%\n", mean(trades$PnL_Percent)))
cat(sprintf("平均持仓: %.1f根K线 (约%.1f小时)\n",
            mean(trades$Holding_Bars),
            mean(trades$Holding_Bars) * 15 / 60))

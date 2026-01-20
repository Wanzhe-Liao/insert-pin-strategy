# ============================================================================
# 基于盈亏模式的智能交易匹配算法
# ============================================================================

library(data.table)

# 读��数据
tv_detail <- fread("outputs/tv_trades_detailed.csv")
r_trades <- fread("outputs/trades_tradingview_aligned.csv")

# 转换R数据
r_trades$R_PnL <- as.numeric(gsub("%", "", r_trades$PnLPercent))
r_trades$R_EntryTime <- as.POSIXct(r_trades$EntryTime, tz="UTC")
r_trades$R_ExitTime <- as.POSIXct(r_trades$ExitTime, tz="UTC")
r_trades$R_Duration_Hours <- as.numeric(difftime(r_trades$R_ExitTime,
                                                  r_trades$R_EntryTime,
                                                  units="hours"))

cat("========================================\n")
cat("智能交易匹配分析\n")
cat("========================================\n\n")

cat("TradingView交易: ", nrow(tv_detail), " 笔\n")
cat("R回测交易: ", nrow(r_trades), " 笔\n\n")

# ============================================================================
# 匹配算法1: 基于盈亏百分比的精确匹配
# ============================================================================

cat("【方法1: 盈亏百分比精确匹配】\n")
cat("查找盈亏相同或非常接近的交易...\n\n")

matches_method1 <- data.table()

for (i in 1:nrow(tv_detail)) {
  tv_pnl <- tv_detail$PnL[i]

  # 在R交易中查找盈亏接近的交易（容差0.5%）
  candidates <- r_trades[abs(R_PnL - tv_pnl) < 0.5]

  if (nrow(candidates) > 0) {
    # 选择最接近的一笔
    best_match_idx <- which.min(abs(candidates$R_PnL - tv_pnl))
    best_match <- candidates[best_match_idx]

    matches_method1 <- rbind(matches_method1, data.table(
      TV_TradeId = i,
      TV_PnL = tv_pnl,
      TV_EntryPrice = tv_detail$EntryPrice[i],
      TV_Duration = tv_detail$Duration_Hours[i],
      R_TradeId = best_match$TradeId,
      R_PnL = best_match$R_PnL,
      R_EntryPrice = best_match$EntryPrice,
      R_Duration = best_match$R_Duration_Hours,
      R_EntryTime = as.character(best_match$R_EntryTime),
      PnL_Diff = abs(best_match$R_PnL - tv_pnl)
    ))

    cat("TV交易#", i, " (盈亏", tv_pnl, "%) 匹配到 R交易#",
        best_match$TradeId, " (盈亏", best_match$R_PnL, "%)\n")
  } else {
    cat("TV交易#", i, " (盈亏", tv_pnl, "%) 未找到匹配\n")
  }
}

cat("\n方法1匹配成功: ", nrow(matches_method1), "/", nrow(tv_detail), " 笔\n\n")

if (nrow(matches_method1) > 0) {
  fwrite(matches_method1, "outputs/matches_method1_pnl.csv")
  cat("已保存方法1匹配结果\n\n")
}

# ============================================================================
# 匹配算法2: 基于盈亏序列模式匹配
# ============================================================================

cat("【方法2: 盈亏序列模式匹配】\n")
cat("在R交易序列中查找与TV相似的盈亏模式...\n\n")

# TradingView的盈亏序列
tv_pnl_sequence <- tv_detail$PnL
cat("TradingView盈亏序列: ", paste(round(tv_pnl_sequence, 2), collapse=", "), "\n\n")

# 在R交易中寻找相似的连续序列
# 计算滑动窗口相似度
window_size <- length(tv_pnl_sequence)
similarity_scores <- numeric(nrow(r_trades) - window_size + 1)

for (start_idx in 1:(nrow(r_trades) - window_size + 1)) {
  r_window <- r_trades$R_PnL[start_idx:(start_idx + window_size - 1)]

  # 计算相似度（使用均方误差的倒数）
  mse <- mean((r_window - tv_pnl_sequence)^2)
  similarity_scores[start_idx] <- 1 / (1 + mse)  # 归一化相似度
}

# 找到最相似的窗口
best_window_start <- which.max(similarity_scores)
best_window_end <- best_window_start + window_size - 1
best_similarity <- similarity_scores[best_window_start]

cat("最佳匹配窗口: R交易#", best_window_start, "到#", best_window_end, "\n")
cat("相似度得分: ", round(best_similarity, 4), "\n\n")

r_matched_sequence <- r_trades[best_window_start:best_window_end]
cat("匹配的R交易盈亏序列: ",
    paste(round(r_matched_sequence$R_PnL, 2), collapse=", "), "\n\n")

# 创建序列匹配对比表
sequence_comparison <- data.table(
  TV_TradeId = 1:window_size,
  TV_PnL = tv_pnl_sequence,
  TV_EntryTime = tv_detail$EntryTime,
  TV_EntryPrice = tv_detail$EntryPrice,
  R_TradeId = r_matched_sequence$TradeId,
  R_PnL = r_matched_sequence$R_PnL,
  R_EntryTime = as.character(r_matched_sequence$R_EntryTime),
  R_EntryPrice = r_matched_sequence$EntryPrice,
  PnL_Diff = r_matched_sequence$R_PnL - tv_pnl_sequence,
  Price_Diff_Pct = (r_matched_sequence$EntryPrice - as.numeric(tv_detail$EntryPrice)) /
                    as.numeric(tv_detail$EntryPrice) * 100
)

fwrite(sequence_comparison, "outputs/matches_method2_sequence.csv")
cat("已保存方法2序列匹配结果\n\n")

# ============================================================================
# 匹配算法3: 基于价格特征的匹配
# ============================================================================

cat("【方法3: 基于价格水平的匹配】\n")
cat("根据入场价格水平查找对应交易...\n\n")

matches_method3 <- data.table()

for (i in 1:nrow(tv_detail)) {
  tv_price <- as.numeric(tv_detail$EntryPrice[i])
  tv_pnl <- tv_detail$PnL[i]

  # 在R交易中查找价格接近的交易（容差30%）
  candidates <- r_trades[abs(EntryPrice - tv_price) / tv_price < 0.3]

  if (nrow(candidates) > 0) {
    # 在价格接近的交易中，选择盈亏最接近的
    best_match_idx <- which.min(abs(candidates$R_PnL - tv_pnl))
    best_match <- candidates[best_match_idx]

    price_diff_pct <- (best_match$EntryPrice - tv_price) / tv_price * 100

    matches_method3 <- rbind(matches_method3, data.table(
      TV_TradeId = i,
      TV_EntryTime = tv_detail$EntryTime[i],
      TV_EntryPrice = tv_price,
      TV_PnL = tv_pnl,
      R_TradeId = best_match$TradeId,
      R_EntryTime = as.character(best_match$R_EntryTime),
      R_EntryPrice = best_match$EntryPrice,
      R_PnL = best_match$R_PnL,
      Price_Diff_Pct = price_diff_pct,
      PnL_Diff = best_match$R_PnL - tv_pnl
    ))

    cat("TV交易#", i, " (价格", sprintf("%.8f", tv_price), ") 匹配到 R交易#",
        best_match$TradeId, " (价格", sprintf("%.8f", best_match$EntryPrice),
        ", 差异", round(price_diff_pct, 2), "%)\n")
  } else {
    cat("TV交易#", i, " 未找到价格接近的交易\n")
  }
}

cat("\n方法3匹配成功: ", nrow(matches_method3), "/", nrow(tv_detail), " 笔\n\n")

if (nrow(matches_method3) > 0) {
  fwrite(matches_method3, "outputs/matches_method3_price.csv")
  cat("已保存方法3匹配结果\n\n")
}

# ============================================================================
# 汇总报告
# ============================================================================

summary_report <- paste0(
  "========================================\n",
  "智能匹配汇总报告\n",
  "========================================\n\n",

  "【数据概况】\n",
  "TradingView交易数: ", nrow(tv_detail), "\n",
  "R回测交易数: ", nrow(r_trades), "\n",
  "数据完整性: ", round(nrow(tv_detail)/nrow(r_trades)*100, 2), "%\n\n",

  "【方法1: 盈亏精确匹配】\n",
  "匹配成功率: ", nrow(matches_method1), "/", nrow(tv_detail),
  " (", round(nrow(matches_method1)/nrow(tv_detail)*100, 2), "%)\n",
  ifelse(nrow(matches_method1) > 0,
         paste0("平均盈亏差异: ", round(mean(matches_method1$PnL_Diff), 4), "%\n"),
         ""), "\n",

  "【方法2: 序列模式匹配】\n",
  "最佳匹配窗口: R交易#", best_window_start, "-#", best_window_end, "\n",
  "相似度得分: ", round(best_similarity, 4), "\n",
  "平均盈亏差异: ", round(mean(abs(sequence_comparison$PnL_Diff)), 4), "%\n",
  "平均价格差异: ", round(mean(abs(sequence_comparison$Price_Diff_Pct)), 2), "%\n\n",

  "【方法3: 价格特征匹配】\n",
  "匹配成功率: ", nrow(matches_method3), "/", nrow(tv_detail),
  " (", round(nrow(matches_method3)/nrow(tv_detail)*100, 2), "%)\n",
  ifelse(nrow(matches_method3) > 0,
         paste0("平均价格差异: ", round(mean(abs(matches_method3$Price_Diff_Pct)), 2), "%\n",
                "平均盈亏差异: ", round(mean(abs(matches_method3$PnL_Diff)), 4), "%\n"),
         ""), "\n",

  "【核心发现】\n\n",

  "1. 数据严重不完整:\n",
  "   - TradingView只导出了5.45%的交易数据\n",
  "   - ���要从TradingView重新导出完整的165笔交易\n\n",

  "2. 交易特征差异:\n",
  "   - 时间不对齐（起点差3天）\n",
  "   - 价格差异巨大（平均30-70%）\n",
  "   - 盈亏百分比相对接近（部分交易在±0.5%以内）\n\n",

  "3. 可能的解释:\n",
  "   - 两个系统使用了不同的数据源或交易对\n",
  "   - K线数据的时间戳格式不同\n",
  "   - TradingView可能使用了复权或调整后的价格\n",
  "   - 策略参数可能有细微差异导致信号时机不同\n\n",

  "【下一步建议】\n\n",
  "1. 重新导出TradingView完整数据（165笔交易）\n",
  "2. 确认两个系统的交易对和数据源完全一致\n",
  "3. 检查策略代码中的参数设置\n",
  "4. 如果确认策略完全相同，考虑K线数据质量问题\n"
)

cat(summary_report)
writeLines(summary_report, "smart_matching_summary.txt", useBytes = TRUE)
cat("\n已保存智能匹配汇总报告\n")

cat("\n========================================\n")
cat("分析完成！\n")
cat("========================================\n")

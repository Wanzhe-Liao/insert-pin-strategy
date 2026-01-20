# 创建Excel友好的对比表

library(data.table)

# 读取结果
results <- fread('outputs/fee_impact_results.csv')

cat("创建对比表...\n")

# ============================================================================
# 1. 总收益对比表
# ============================================================================

wide_return <- dcast(results, timeframe ~ fee_pct, value.var = 'total_return_pct')
setnames(wide_return, old = c("timeframe", "0", "0.05", "0.075", "0.1"),
         new = c("时间框架", "无费率", "0.05%费率", "0.075%费率", "0.1%费率"))

# 添加衰减列
wide_return[, 收益衰减 := round(无费率 - `0.075%费率`, 2)]
wide_return[, 衰减百分比 := round((收益衰减 / 无费率) * 100, 1)]

# 排序
setorder(wide_return, -`0.075%费率`)

# 保存
write.csv(wide_return, 'outputs/fee_comparison_return.csv', row.names = FALSE)
cat("  [OK] 总收益对比表: fee_comparison_return.csv\n")

# ============================================================================
# 2. 年化收益对比表
# ============================================================================

wide_annual <- dcast(results, timeframe ~ fee_pct, value.var = 'annual_return_pct')
setnames(wide_annual, old = c("timeframe", "0", "0.05", "0.075", "0.1"),
         new = c("时间框架", "无费率", "0.05%费率", "0.075%费率", "0.1%费率"))

# 排序
setorder(wide_annual, -`0.075%费率`)

write.csv(wide_annual, 'outputs/fee_comparison_annual.csv', row.names = FALSE)
cat("  [OK] 年化收益对比表: fee_comparison_annual.csv\n")

# ============================================================================
# 3. 综合性能表（0.075%费率）
# ============================================================================

target <- results[fee_pct == 0.075]
setorder(target, -total_return_pct)

summary_table <- data.table(
  排名 = 1:nrow(target),
  时间框架 = target$timeframe,
  信号数 = target$signals_count,
  交易数 = target$trades_count,
  总收益率 = sprintf('%.2f%%', target$total_return_pct),
  年化收益率 = sprintf('%.2f%%', target$annual_return_pct),
  胜率 = sprintf('%.1f%%', target$win_rate_pct),
  平均收益 = sprintf('%.2f%%', target$avg_return_pct),
  最大回撤 = sprintf('%.2f%%', target$max_drawdown_pct),
  盈亏比 = round(target$profit_factor, 2),
  手续费占比 = sprintf('%.2f%%', target$fee_ratio_pct),
  平均持仓K线数 = round(target$avg_holding_bars, 1)
)

write.csv(summary_table, 'outputs/performance_summary_0075fee.csv', row.names = FALSE)
cat("  [OK] 综合性能表: performance_summary_0075fee.csv\n")

# ============================================================================
# 4. 手续费敏感度表
# ============================================================================

# 计算每个时间框架的敏感度
sensitivity_data <- list()

for (tf in unique(results$timeframe)) {
  tf_data <- results[timeframe == tf]
  setorder(tf_data, fee_pct)

  # 线性拟合
  fit <- lm(total_return_pct ~ fee_pct, data = tf_data)

  # 敏感度（每0.01%费率的影响）
  sensitivity <- coef(fit)[2] / 100

  # 盈亏平衡点
  breakeven <- ifelse(coef(fit)[2] != 0, -coef(fit)[1] / coef(fit)[2], NA)

  # 0费率收益
  zero_return <- tf_data[fee_pct == 0, total_return_pct]

  # 0.075%费率收益
  target_return <- tf_data[fee_pct == 0.075, total_return_pct]

  sensitivity_data[[tf]] <- data.table(
    时间框架 = tf,
    无费率收益 = sprintf('%.2f%%', zero_return),
    目标费率收益 = sprintf('%.2f%%', target_return),
    收益衰减 = sprintf('%.2f%%', zero_return - target_return),
    相对衰减 = sprintf('%.1f%%', ((zero_return - target_return) / zero_return) * 100),
    敏感度 = sprintf('%.4f%%/0.01%%', sensitivity),
    盈亏平衡点 = sprintf('%.3f%%', breakeven)
  )
}

sensitivity_table <- rbindlist(sensitivity_data)
setorder(sensitivity_table, -目标费率收益)

write.csv(sensitivity_table, 'outputs/fee_sensitivity_analysis.csv', row.names = FALSE)
cat("  [OK] 手续费敏感度表: fee_sensitivity_analysis.csv\n")

# ============================================================================
# 显示汇总
# ============================================================================

cat("\n=== 总收益对比 ===\n")
print(wide_return)

cat("\n=== 综合性能（0.075%费率）===\n")
print(summary_table)

cat("\n=== 手续费敏感度 ===\n")
print(sensitivity_table)

cat("\n所有对比表已生成完成！\n")

# 快速修复脚本：应用方案A（信号窗口修复）
# =====================================================
# 这个脚本会：
# 1. 读取原代码
# 2. 应用信号窗口修复
# 3. 保存修复后的版本
# 4. 运行测试并生成对比报告
# =====================================================

cat("\n")
cat("=" %R% 80, "\n", sep="")
cat("快速修复：应用方案A（信号窗口修复）\n")
cat("=" %R% 80, "\n\n", sep="")

`%R%` <- function(x, n) paste(rep(x, n), collapse = "")

# 1. 备份原文件
cat("步骤1: 备份原文件...\n")
backup_path <- "backtest_tradingview_aligned_before_fix.R"
file.copy(
  "backtest_tradingview_aligned.R",
  backup_path,
  overwrite = TRUE
)
cat(sprintf("  OK 已备份到: %s\n\n", backup_path))

# 2. 读取原文件
cat("步骤2: 读取原文件...\n")
lines <- readLines("backtest_tradingview_aligned.R")
cat(sprintf("  OK 共%d行代码\n\n", length(lines)))

# 3. 应用修复
cat("步骤3: 应用信号窗口修复...\n")

# 找到需要修改的行
target_line_1 <- which(grepl("window_high <- RcppRoll::roll_max", lines, fixed = FALSE))[1]
target_line_2 <- which(grepl("drop_percent <- \\(window_high - low_vec\\)", lines, fixed = FALSE))[1]

cat(sprintf("  找到目标行: Line %d 和 Line %d\n", target_line_1, target_line_2))

# 在window_high和drop_percent之间插入新代码
if (!is.na(target_line_1) && !is.na(target_line_2) && target_line_2 > target_line_1) {

  # 原有的行
  original_window_line <- lines[target_line_1]
  original_drop_line <- lines[target_line_2]

  cat("\n  原代码:\n")
  cat(sprintf("    Line %d: %s\n", target_line_1, original_window_line))
  cat(sprintf("    Line %d: %s\n", target_line_2, original_drop_line))

  # 新增的lag操作
  new_line <- "  window_high_prev <- c(NA, window_high[-n])  # 排除当前K线，对齐Pine Script的ta.highest()[1]"

  # 修改drop_percent行，使用window_high_prev
  modified_drop_line <- gsub("window_high", "window_high_prev", original_drop_line)

  # 插入新行
  lines <- c(
    lines[1:target_line_1],
    "",
    paste0("  # FIX 关键修复：排除当前K线，对齐Pine Script的ta.highest()[1]行为"),
    paste0("  # Pine Script: windowHigh = ta.highest(high, lookbackBars)[1]"),
    paste0("  # [1]表示向前偏移1位，即排除当前K线，只看过去lookbackBars根K线"),
    new_line,
    "",
    lines[(target_line_1+1):(target_line_2-1)],
    modified_drop_line,
    lines[(target_line_2+1):length(lines)]
  )

  cat("\n  修复后代码:\n")
  cat(sprintf("    Line %d: %s\n", target_line_1, original_window_line))
  cat(sprintf("    Line %d: %s\n", target_line_1+6, new_line))
  cat(sprintf("    Line %d: %s\n", target_line_2+6, modified_drop_line))

  # 保存修复后的文件
  writeLines(lines, "backtest_tradingview_aligned.R")
  cat("\n  OK 修复完成并保存\n\n")

} else {
  cat("  FAIL 错误: 无法找到目标行，修复失败\n\n")
  stop("修复失败")
}

# 4. 重新加载修复后的代码
cat("步骤4: 加载修复后的代码...\n")
source("backtest_tradingview_aligned.R")
cat("  OK 代码已加载\n\n")

# 5. 运行测试
cat("步骤5: 运行回测测试...\n")
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

result_fixed <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE
)

cat(sprintf("  OK 回测完成\n"))
cat(sprintf("  交易数量: %d\n", result_fixed$TradeCount))
cat(sprintf("  信号数量: %d\n", result_fixed$SignalCount))
cat(sprintf("  胜率: %.2f%%\n\n", result_fixed$WinRate))

# 6. 生成交易数据
cat("步骤6: 生成交易数据...\n")
trades_fixed <- format_trades_df(result_fixed)
write.csv(trades_fixed, "r_trades_after_fix_a.csv", row.names = FALSE)
cat("  OK 已保存: r_trades_after_fix_a.csv\n\n")

# 7. 对比分析
cat("步骤7: 对比分析...\n")
cat("=" %R% 80, "\n", sep="")

# 读取TV数据
tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
r_trades <- trades_fixed

cat("\n【交易数量对比】\n")
cat(sprintf("  TradingView: %d笔\n", nrow(tv_trades)))
cat(sprintf("  R修复后:     %d笔\n", nrow(r_trades)))
if(nrow(tv_trades) == nrow(r_trades)) {
  cat("  OK 交易数量: 100%对齐\n\n")
} else {
  cat(sprintf("  FAIL 交易数量: 不对齐 (差%d笔)\n\n", abs(nrow(tv_trades) - nrow(r_trades))))
}

# 逐笔对比
cat("【逐笔详细对比】\n")
cat(rep("-", 80), "\n", sep="")

entry_time_match <- 0
entry_price_match <- 0
exit_time_match <- 0
exit_price_match <- 0

for(i in 1:min(nrow(tv_trades), nrow(r_trades))) {
  tv <- tv_trades[i, ]
  r <- r_trades[i, ]

  cat(sprintf("\n交易 #%d:\n", i))

  # 入场时间
  tv_entry_time <- as.POSIXct(tv$EntryTime, format="%Y-%m-%d %H:%M:%S")
  r_entry_time <- as.POSIXct(r$EntryTime, format="%Y-%m-%d %H:%M:%S")
  time_diff_mins <- as.numeric(difftime(tv_entry_time, r_entry_time, units="mins"))

  cat(sprintf("  入场时间: TV=%s, R=%s",
              format(tv_entry_time, "%Y-%m-%d %H:%M"),
              format(r_entry_time, "%Y-%m-%d %H:%M")))

  if(abs(time_diff_mins) < 1) {
    cat(" OK\n")
    entry_time_match <- entry_time_match + 1
  } else {
    cat(sprintf(" FAIL (差%.0f分钟)\n", time_diff_mins))
  }

  # 入场价格
  tv_entry_price <- as.numeric(tv$EntryPrice)
  r_entry_price <- as.numeric(r$EntryPrice)
  price_diff_pct <- abs(tv_entry_price - r_entry_price) / tv_entry_price * 100

  cat(sprintf("  入场价格: TV=%.8f, R=%.8f",
              tv_entry_price, r_entry_price))

  if(price_diff_pct < 0.01) {
    cat(" OK\n")
    entry_price_match <- entry_price_match + 1
  } else {
    cat(sprintf(" FAIL (差%.4f%%)\n", price_diff_pct))
  }

  # 出场时间
  tv_exit_time <- as.POSIXct(tv$ExitTime, format="%Y-%m-%d %H:%M:%S")
  r_exit_time <- as.POSIXct(r$ExitTime, format="%Y-%m-%d %H:%M:%S")
  exit_diff_mins <- as.numeric(difftime(tv_exit_time, r_exit_time, units="mins"))

  cat(sprintf("  出场时间: TV=%s, R=%s",
              format(tv_exit_time, "%Y-%m-%d %H:%M"),
              format(r_exit_time, "%Y-%m-%d %H:%M")))

  if(abs(exit_diff_mins) < 1) {
    cat(" OK\n")
    exit_time_match <- exit_time_match + 1
  } else {
    cat(sprintf(" FAIL (差%.0f分钟)\n", exit_diff_mins))
  }

  # 出场价格
  tv_exit_price <- as.numeric(tv$ExitPrice)
  r_exit_price <- as.numeric(gsub(",", "", r$ExitPrice))
  exit_price_diff_pct <- abs(tv_exit_price - r_exit_price) / tv_exit_price * 100

  cat(sprintf("  出场价格: TV=%.8f, R=%.8f",
              tv_exit_price, r_exit_price))

  if(exit_price_diff_pct < 0.01) {
    cat(" OK\n")
    exit_price_match <- exit_price_match + 1
  } else {
    cat(sprintf(" FAIL (差%.4f%%)\n", exit_price_diff_pct))
  }
}

cat("\n")
cat(rep("=", 80), "\n", sep="")
cat("【对齐率汇总】\n")
cat(rep("=", 80), "\n", sep="")

n_trades <- min(nrow(tv_trades), nrow(r_trades))

cat(sprintf("\n  交易数量: %d vs %d", nrow(tv_trades), nrow(r_trades)))
if(nrow(tv_trades) == nrow(r_trades)) {
  cat(" OK 100%%\n")
} else {
  cat(" FAIL\n")
}

cat(sprintf("  入场时间: %d/%d", entry_time_match, n_trades))
if(entry_time_match == n_trades) {
  cat(" OK 100%%\n")
} else {
  cat(sprintf(" FAIL %.1f%%\n", entry_time_match / n_trades * 100))
}

cat(sprintf("  入场价格: %d/%d", entry_price_match, n_trades))
if(entry_price_match == n_trades) {
  cat(" OK 100%%\n")
} else {
  cat(sprintf(" FAIL %.1f%%\n", entry_price_match / n_trades * 100))
}

cat(sprintf("  出场时间: %d/%d", exit_time_match, n_trades))
if(exit_time_match == n_trades) {
  cat(" OK 100%%\n")
} else {
  cat(sprintf(" FAIL %.1f%%\n", exit_time_match / n_trades * 100))
}

cat(sprintf("  出场价格: %d/%d", exit_price_match, n_trades))
if(exit_price_match == n_trades) {
  cat(" OK 100%%\n")
} else {
  cat(sprintf(" FAIL %.1f%%\n", exit_price_match / n_trades * 100))
}

cat("\n")
cat(rep("=", 80), "\n", sep="")

# 8. 生成总结报告
cat("\n【修复效果总结】\n\n")

if(entry_time_match == n_trades && entry_price_match == n_trades &&
   exit_time_match == n_trades && nrow(tv_trades) == nrow(r_trades)) {
  cat("🎉 恭喜！已达到100%完全对齐！\n\n")
} else {
  cat("修复方案A已应用，但尚未达到100%对齐。\n\n")

  if(entry_time_match / n_trades > 0.778) {
    cat("OK 入场时间对齐率有提升（原77.8%）\n")
  } else if(entry_time_match / n_trades == 0.778) {
    cat("- 入场时间对齐率无变化（仍为77.8%）\n")
  } else {
    cat("FAIL 入场时间对齐率下降了\n")
  }

  if(entry_price_match / n_trades > 0.889) {
    cat("OK 入场价格对齐率有提升（原88.9%）\n")
  } else if(entry_price_match / n_trades == 0.889) {
    cat("- 入场价格对齐率无变化（仍为88.9%）\n")
  } else {
    cat("FAIL 入场价格对齐率下降了\n")
  }

  if(exit_time_match / n_trades > 0.222) {
    cat("OK 出场时间对齐率有提升（原22.2%）\n")
  } else if(exit_time_match / n_trades == 0.222) {
    cat("- 出场时间对齐率无变化（仍为22.2%）\n")
  } else {
    cat("FAIL 出场时间对齐率下降了\n")
  }

  cat("\n下一步建议:\n")
  cat("  1. 如果对齐率提升: 继续应用方案B（出场价格修复）\n")
  cat("  2. 如果对齐率下降: 恢复备份，重新分析Pine Script源代码\n")
  cat("  3. 如果对齐率无变化: 问题可能在其他地方，需要深入调试\n\n")
}

cat("相关文件:\n")
cat("  - 备份文件: backtest_tradingview_aligned_before_fix.R\n")
cat("  - 修复后代码: backtest_tradingview_aligned.R\n")
cat("  - 修复后交易: r_trades_after_fix_a.csv\n")
cat("  - 详细报告: CODE_REVIEW_REPORT.md\n")
cat("  - 修复方案: FIX_PROPOSALS.md\n\n")

cat("完成!\n\n")

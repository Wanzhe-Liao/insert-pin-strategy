# 深度调试V2：验证lookbackBars计算逻辑
# 核心发现：generate_drop_signals()中 lookbackBars = lookbackDays（不转换天数）

library(xts)
library(RcppRoll)

# 加载数据
load('data/liaochu.RData')
data <- cryptodata[["PEPEUSDT_15m"]]

cat("========================================\n")
cat("核心问题验证：lookbackBars计算\n")
cat("========================================\n\n")

# 测试1：R脚本的实际行为
source('backtest_tradingview_aligned.R')

cat("测试1: generate_drop_signals()的实际行为\n")
cat("输入参数: lookbackDays = 3\n")

# 生成信号
signals <- generate_drop_signals(data, lookbackDays=3, minDropPercent=20)

# 分析第一个信号
first_signal_idx <- which(signals)[1]
cat("第一个信号索引:", first_signal_idx, "\n")
cat("第一个信号时间:", as.character(index(data)[first_signal_idx]), "\n\n")

# 测试2：手动计算，验证lookbackBars=3（3根K线）
cat("测试2: 手动验证lookbackBars=3的假设\n")

for (i in 1:10) {
  current_time <- index(data)[i]
  current_low <- as.numeric(data[i, "Low"])

  cat(sprintf("\nK线 #%d (%s):\n", i, as.character(current_time)))
  cat(sprintf("  Low: %.8f\n", current_low))

  if (i > 3) {  # 假设lookbackBars=3
    # 前3根K线的最高价
    window_high <- max(data[(i-3):(i-1), "High"])
    drop_pct <- (window_high - current_low) / window_high * 100
    signal <- drop_pct >= 20

    cat(sprintf("  窗口 [%d,%d] 最高价: %.8f\n", i-3, i-1, window_high))
    cat(sprintf("  跌幅: %.2f%%\n", drop_pct))
    cat(sprintf("  信号: %s\n", signal))

    if (signal) {
      cat("  *** 这是第一个信号！***\n")
    }
  } else {
    cat("  索引 <= 3，跳过\n")
  }
}

# 测试3：对比lookbackBars=288（3天×96根K线）
cat("\n\n测试3: 如果lookbackBars=288（真正的3天）\n")

lookbackBars_3days <- 3 * 24 * 4  # 288根K线
cat("lookbackBars =", lookbackBars_3days, "\n")

first_possible_idx <- lookbackBars_3days + 1
cat("第一个可能产生信号的索引:", first_possible_idx, "\n")

if (first_possible_idx <= nrow(data)) {
  first_possible_time <- index(data)[first_possible_idx]
  cat("第一个可能产生信号的时间:", as.character(first_possible_time), "\n")
} else {
  cat("数据不足，无法计算\n")
}

# 测试4：检查2023-05-06的信号（TradingView第一笔）
cat("\n\n测试4: 检查2023-05-06的所有K线信号\n")

may6_indices <- which(format(index(data), "%Y-%m-%d") == "2023-05-06")
cat("2023-05-06 K线索引范围:", min(may6_indices), "到", max(may6_indices), "\n")
cat("总K线数:", length(may6_indices), "\n\n")

may6_signals <- signals[may6_indices]
cat("2023-05-06 信号数:", sum(may6_signals), "\n")

if (sum(may6_signals) > 0) {
  signal_indices <- may6_indices[may6_signals]
  cat("信号出现的索引:", paste(signal_indices, collapse=", "), "\n")
  cat("信号出现的时间:\n")
  for (idx in signal_indices) {
    cat("  ", as.character(index(data)[idx]), "\n")
  }
}

# 测试5：检查2023-05-09的信号（R第一笔）
cat("\n\n测试5: 检查2023-05-09的所有K线信号\n")

may9_indices <- which(format(index(data), "%Y-%m-%d") == "2023-05-09")
cat("2023-05-09 K线索引范围:", min(may9_indices), "到", max(may9_indices), "\n")

may9_signals <- signals[may9_indices]
cat("2023-05-09 信号数:", sum(may9_signals), "\n")

if (sum(may9_signals) > 0) {
  first_may9_signal_idx <- may9_indices[which(may9_signals)[1]]
  cat("第一个信号索引:", first_may9_signal_idx, "\n")
  cat("第一个信号时间:", as.character(index(data)[first_may9_signal_idx]), "\n")
}

# 关键分析
cat("\n========================================\n")
cat("关键发现总结\n")
cat("========================================\n\n")

cat("1. lookbackBars的实际值:\n")
cat("   - 代码中: lookbackBars = lookbackDays = 3\n")
cat("   - 含义: 向前看3根K线（不是3天！）\n")
cat("   - 如果是3天应该是: 3 × 96 = 288根K线\n\n")

cat("2. 第一个信号位置:\n")
cat("   - 索引:", first_signal_idx, "\n")
cat("   - 时间:", as.character(index(data)[first_signal_idx]), "\n")
cat("   - 日期:", format(index(data)[first_signal_idx], "%Y-%m-%d"), "\n\n")

cat("3. 为什么R第一笔在2023-05-09?\n")
cat("   - 需要检查回测函数是否正确执行了2023-05-06的信号\n")
cat("   - 可能原因：\n")
cat("     a) 2023-05-06有信号，但被持仓管理逻辑忽略了\n")
cat("     b) 2023-05-06有信号，但止盈/止损在同一K线触发\n")
cat("     c) 信号生成时间与交易执行时间的对齐问题\n\n")

cat("4. TradingView vs R的差异:\n")
cat("   - TradingView第一笔: 2023-05-06 (Excel 45052)\n")
cat("   - R第一笔: 2023-05-09 02:14:59\n")
cat("   - R第一个信号: ", as.character(index(data)[first_signal_idx]), "\n")
cat("   - 时间差: ", difftime(as.Date("2023-05-09"), as.Date("2023-05-06"), units="days"), "天\n\n")

# 保存报告
sink("time_diff_debug_report.txt")

cat("========================================\n")
cat("R vs TradingView 时间差异深度调试报告\n")
cat("生成时间:", as.character(Sys.time()), "\n")
cat("========================================\n\n")

cat("【问题描述】\n")
cat("TradingView第一笔交易: 2023-05-06 (Excel序列号45052)\n")
cat("R第一笔交易: 2023-05-09 02:14:59\n")
cat("时间差异: 约3天\n\n")

cat("【数据验证】\n")
cat("R数据起始时间:", as.character(index(data)[1]), "\n")
cat("R数据总K线数:", nrow(data), "\n")
cat("2023-05-06 K线数:", length(may6_indices), "\n")
cat("2023-05-06 K线范围:", as.character(index(data)[min(may6_indices)]), "到",
    as.character(index(data)[max(may6_indices)]), "\n\n")

cat("【关键发现】lookbackBars计算错误\n")
cat("代码位置: backtest_tradingview_aligned.R 第100行\n")
cat("问题代码: lookbackBars <- lookbackDays  # 直接使用，不转换\n\n")

cat("实际行为:\n")
cat("  - 输入: lookbackDays = 3\n")
cat("  - 计算: lookbackBars = 3（直接赋值，未转换）\n")
cat("  - 含义: 向前看3根K线\n\n")

cat("期望行为:\n")
cat("  - 输入: lookbackDays = 3（天）\n")
cat("  - 计算: lookbackBars = 3 × 96 = 288根K线（15分钟K线，每天96根）\n")
cat("  - 含义: 向前看3天的数据\n\n")

cat("【信号生成验证】\n")
cat("使用lookbackBars=3（3根K线）:\n")
cat("  - 第一个信号索引:", first_signal_idx, "\n")
cat("  - 第一个信号时间:", as.character(index(data)[first_signal_idx]), "\n")
cat("  - 第一个信号日期:", format(index(data)[first_signal_idx], "%Y-%m-%d"), "\n\n")

cat("2023-05-06 信号统计:\n")
cat("  - 总信号数:", sum(may6_signals), "\n")
if (sum(may6_signals) > 0) {
  cat("  - 信号时间:\n")
  signal_indices <- may6_indices[may6_signals]
  for (idx in signal_indices) {
    cat("      ", as.character(index(data)[idx]), "\n")
  }
}
cat("\n")

cat("2023-05-09 信号统计:\n")
cat("  - 总信号数:", sum(may9_signals), "\n")
if (sum(may9_signals) > 0) {
  first_may9_signal_idx <- may9_indices[which(may9_signals)[1]]
  cat("  - 第一个信号索引:", first_may9_signal_idx, "\n")
  cat("  - 第一个信号时间:", as.character(index(data)[first_may9_signal_idx]), "\n")
}
cat("\n")

cat("【根本原因分析】\n")
cat("虽然代码注释中提到了Pine Script的命名混淆，但这里的实现可能是错误的:\n\n")

cat("1. Pine Script行为（需验证）:\n")
cat("   - 如果Pine中lookbackDays=3确实表示3根K线，那R的实现是正确的\n")
cat("   - 但这与常规理解的'Days'不符\n\n")

cat("2. R实际计算的信号:\n")
cat("   - 只看前3根K线（45分钟的历史数据）\n")
cat("   - 与TradingView的'3天'含义不符\n\n")

cat("3. 为什么第一笔是2023-05-09而不是2023-05-06?\n")
cat("   - 即使2023-05-06有信号（索引", first_signal_idx, "）\n")
cat("   - 也需要检查backtest_tradingview_aligned()函数\n")
cat("   - 确认是否正确执行了这些信号\n\n")

cat("【下一步调试】\n")
cat("需要追踪backtest函数的交易执行逻辑:\n")
cat("1. 检查2023-05-06的信号是否被正确识别\n")
cat("2. 检查这些信号是否被持仓管理逻辑忽略\n")
cat("3. 检查止盈/止损是否在入场后立即触发\n")
cat("4. 对比TradingView的Pine Script确认lookbackDays的真实含义\n\n")

cat("【建议修复】\n")
cat("如果lookbackDays应该表示'天数':\n")
cat("  修改第100行为:\n")
cat("  lookbackBars <- lookbackDays * 96  # 15分钟K线，每天96根\n\n")

cat("如果Pine Script确实将lookbackDays当作K线数:\n")
cat("  重命名参数以避免混淆:\n")
cat("  generate_drop_signals(data, lookbackBars=3, minDropPercent=20)\n")

sink()

cat("\n调试报告已保存: time_diff_debug_report.txt\n")

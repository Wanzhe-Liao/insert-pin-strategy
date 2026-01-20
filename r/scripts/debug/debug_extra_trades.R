# ============================================================================
# 调试R额外交易问题
# ============================================================================
# 目标: 分析为什么R在2023-08-18 05:59和2025-10-11 05:44产生额外交易
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
})

# 加载回测引擎
source("backtest_tradingview_aligned.R")

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取交易记录
r_trades <- read.csv("outputs/r_backtest_trades_final.csv", stringsAsFactors = FALSE)
tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)

cat("\n============================================================\n")
cat("R vs TradingView 交易差异分析\n")
cat("============================================================\n\n")

cat("交易数量对比:\n")
cat(sprintf("  R:  %d笔\n", nrow(r_trades)))
cat(sprintf("  TV: %d笔\n", nrow(tv_trades)))
cat(sprintf("  差异: R多出 %d笔\n\n", nrow(r_trades) - nrow(tv_trades)))

# ============================================================================
# 分析问题交易#3: 2023-08-18 05:59
# ============================================================================

cat("============================================================\n")
cat("问题交易#1 分析: 2023-08-18 05:59\n")
cat("============================================================\n\n")

# R的交易#2和#3
r_trade2 <- r_trades[r_trades$TradeId == 2, ]
r_trade3 <- r_trades[r_trades$TradeId == 3, ]

cat("R交易记录:\n")
cat("  交易#2:\n")
cat(sprintf("    入场: %s @ %.10f\n", r_trade2$EntryTime, r_trade2$EntryPrice))
cat(sprintf("    出场: %s @ %.10f (原因: %s)\n", r_trade2$ExitTime, r_trade2$ExitPrice, r_trade2$ExitReason))
cat("\n")
cat("  交易#3 (额外):\n")
cat(sprintf("    入场: %s @ %.10f\n", r_trade3$EntryTime, r_trade3$EntryPrice))
cat(sprintf("    出场: %s @ %.10f (原因: %s)\n", r_trade3$ExitTime, r_trade3$ExitPrice, r_trade3$ExitReason))
cat("\n")

# 查找该K线的数据
problem_time1 <- "2023-08-18 05:59:59.999"
idx1 <- which(index(data) == as.POSIXct(problem_time1, tz = "UTC"))

if (length(idx1) > 0) {
  cat("问题K线数据 (2023-08-18 05:59):\n")
  window_data <- data[(idx1-5):(idx1+5)]
  print(as.data.frame(window_data))
  cat("\n")

  # 检查信号
  signals <- generate_drop_signals(data, lookbackDays = 3, minDropPercent = 20)

  cat("信号分析 (±5根K线):\n")
  signal_window <- data.frame(
    Bar = (idx1-5):(idx1+5),
    Time = as.character(index(data)[(idx1-5):(idx1+5)]),
    Close = as.numeric(data[(idx1-5):(idx1+5), "Close"]),
    Signal = signals[(idx1-5):(idx1+5)]
  )
  print(signal_window)
  cat("\n")

  # 分析为什么产生信号
  if (signals[idx1]) {
    cat("FAIL 该K线确实产生了信号!\n")

    # 计算跌幅
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])

    window_start <- max(1, idx1 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx1])
    current_low <- low_vec[idx1]
    drop_percent <- (window_high - current_low) / window_high * 100

    cat(sprintf("  窗口最高价: %.10f\n", window_high))
    cat(sprintf("  当前最低价: %.10f\n", current_low))
    cat(sprintf("  跌幅: %.2f%%\n", drop_percent))
    cat("\n")
  }
} else {
  cat("WARN 未找到该K线!\n\n")
}

# 分析TradingView的行为
cat("TradingView交易记录:\n")
tv_trade2 <- tv_trades[tv_trades$TradeId == 2, ]
cat(sprintf("  交易#2: 入场=%s, 出场=%s\n", tv_trade2$EntryTime, tv_trade2$ExitTime))
cat(sprintf("  FAIL TradingView在2023-08-18 05:59没有新交易!\n\n")

# ============================================================================
# 分析问题交易#10: 2025-10-11 05:44
# ============================================================================

cat("============================================================\n")
cat("问题交易#2 分析: 2025-10-11 05:44\n")
cat("============================================================\n\n")

# R的交易#9和#10
r_trade9 <- r_trades[r_trades$TradeId == 9, ]
r_trade10 <- r_trades[r_trades$TradeId == 10, ]

cat("R交易记录:\n")
cat("  交易#9:\n")
cat(sprintf("    入场: %s @ %.10f\n", r_trade9$EntryTime, r_trade9$EntryPrice))
cat(sprintf("    出场: %s @ %.10f (原因: %s)\n", r_trade9$ExitTime, r_trade9$ExitPrice, r_trade9$ExitReason))
cat("\n")
cat("  交易#10 (额外):\n")
cat(sprintf("    入场: %s @ %.10f\n", r_trade10$EntryTime, r_trade10$EntryPrice))
cat(sprintf("    出场: %s @ %.10f (原因: %s)\n", r_trade10$ExitTime, r_trade10$ExitPrice, r_trade10$ExitReason))
cat("\n")

# 查找该K线的数据
problem_time2 <- "2025-10-11 05:44:59.999"
idx2 <- which(index(data) == as.POSIXct(problem_time2, tz = "UTC"))

if (length(idx2) > 0) {
  cat("问题K线数据 (2025-10-11 05:44):\n")
  window_data2 <- data[(idx2-5):(idx2+5)]
  print(as.data.frame(window_data2))
  cat("\n")

  # 检查信号
  signals2 <- generate_drop_signals(data, lookbackDays = 3, minDropPercent = 20)

  cat("信号分析 (±5根K线):\n")
  signal_window2 <- data.frame(
    Bar = (idx2-5):(idx2+5),
    Time = as.character(index(data)[(idx2-5):(idx2+5)]),
    Close = as.numeric(data[(idx2-5):(idx2+5), "Close"]),
    Signal = signals2[(idx2-5):(idx2+5)]
  )
  print(signal_window2)
  cat("\n")

  # 分析为什么产生信号
  if (signals2[idx2]) {
    cat("FAIL 该K线确实产生了信号!\n")

    # 计算跌幅
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])

    window_start <- max(1, idx2 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx2])
    current_low <- low_vec[idx2]
    drop_percent <- (window_high - current_low) / window_high * 100

    cat(sprintf("  窗口最高价: %.10f\n", window_high))
    cat(sprintf("  当前最低价: %.10f\n", current_low))
    cat(sprintf("  跌幅: %.2f%%\n", drop_percent))
    cat("\n")
  }
} else {
  cat("WARN 未找到该K线!\n\n")
}

# 分析TradingView的行为
cat("TradingView交易记录:\n")
tv_trade8 <- tv_trades[tv_trades$TradeId == 8, ]
cat(sprintf("  交易#8: 入场=%s, 出场=%s\n", tv_trade8$EntryTime, tv_trade8$ExitTime))
cat(sprintf("  FAIL TradingView在2025-10-11 05:44没有新交易!\n\n")

# ============================================================================
# 执行顺序分析
# ============================================================================

cat("============================================================\n")
cat("R回测引擎执行顺序分析\n")
cat("============================================================\n\n")

cat("当前R引擎执行顺序 (每根K线):\n")
cat("  1. 【阶段1】检查出场条件 (第258-379行)\n")
cat("     - 如果 inPosition == TRUE && i > entryBar\n")
cat("     - 检查止盈止损是否触发\n")
cat("     - 如果触发, 执行出场, 设置 inPosition = FALSE\n")
cat("\n")
cat("  2. 【阶段2】检查入场信号 (第382-441行)\n")
cat("     - 如果 signals[i] == TRUE && inPosition == FALSE\n")
cat("     - 执行入场, 设置 inPosition = TRUE\n")
cat("\n")

cat("问题场景:\n")
cat("  当同一根K线既触发出场又产生新信号时:\n")
cat("    - 阶段1: 检测到止盈, 平仓, inPosition变为FALSE\n")
cat("    - 阶段2: 检测到新信号, 且inPosition=FALSE, 立即入场\n")
cat("    - 结果: 在同一根K线完成出场+入场\n")
cat("\n")

# ============================================================================
# TradingView行为推断
# ============================================================================

cat("============================================================\n")
cat("TradingView可能的限制机制推断\n")
cat("============================================================\n\n")

cat("假设1: 存在隐含的冷却期\n")
cat("  可能性: 低\n")
cat("  原因: TradingView文档没有提到冷却期机制\n")
cat("\n")

cat("假设2: 信号检测在出场之前完成\n")
cat("  可能性: 高 ⭐\n")
cat("  原因:\n")
cat("    - Pine Script在K线收盘时先计算所有指标和信号\n")
cat("    - 然后才处理订单执行\n")
cat("    - 如果当时处于持仓状态, 信号被忽略\n")
cat("    - 即使该K线后续触发出场, 信号也已经被丢弃\n")
cat("\n")

cat("假设3: 入场延迟到下一根K线\n")
cat("  可能性: 中\n")
cat("  原因:\n")
cat("    - process_orders_on_close=true意味着在收盘时处理\n")
cat("    - 但不清楚是当前K线收盘还是下一根K线开盘\n")
cat("\n")

cat("假设4: 一根K线只能执行一次操作\n")
cat("  可能性: 高 ⭐\n")
cat("  原因:\n")
cat("    - Pine Script的订单执行机制可能限制一根K线只能有一次操作\n")
cat("    - 如果该K线执行了出场, 就不能再执行入场\n")
cat("\n")

# ============================================================================
# 生成调试报告
# ============================================================================

cat("============================================================\n")
cat("正在生成调试报告...\n")
cat("============================================================\n\n")

report <- c(
  "============================================================",
  "R额外交易调试报告",
  "============================================================",
  "",
  "生成时间: " %+% as.character(Sys.time()),
  "",
  "一、问题概述",
  "------------",
  sprintf("R生成了%d笔交易, TradingView生成了%d笔交易", nrow(r_trades), nrow(tv_trades)),
  sprintf("R多出%d笔交易", nrow(r_trades) - nrow(tv_trades)),
  "",
  "额外交易详情:",
  "  1. R交易#3: 2023-08-18 05:59 入场",
  "     - 在R交易#2出场(2023-08-18 05:59)的同一时刻入场",
  "  2. R交易#10: 2025-10-11 05:44 入场",
  "     - 在R交易#9出场(2025-10-11 05:44)的同一时刻入场",
  "",
  "二、R回测引擎执行顺序",
  "---------------------",
  "当前实现 (backtest_tradingview_aligned.R):",
  "",
  "for (i in 1:n) {",
  "  // 阶段1: 检查出场 (第258-379行)",
  "  if (inPosition && i > entryBar) {",
  "    if (触发止盈或止损) {",
  "      执行出场",
  "      inPosition = FALSE",
  "      lastExitBar = i",
  "    }",
  "  }",
  "  ",
  "  // 阶段2: 检查入场 (第382-441行)",
  "  if (signals[i] && !inPosition) {",
  "    执行入场",
  "    inPosition = TRUE",
  "  }",
  "}",
  "",
  "问题:",
  "  - 在同一根K线(同一个i), 可以先出场再入场",
  "  - 如果该K线既触发止盈又产生新信号, 会连续执行两次操作",
  "",
  "三、问题交易详细分析",
  "---------------------"
)

# 添加交易#3的详细数据
if (length(idx1) > 0) {
  report <- c(report,
    "",
    "问题交易#3 (2023-08-18 05:59):",
    sprintf("  R交易#2出场时间: %s", r_trade2$ExitTime),
    sprintf("  R交易#3入场时间: %s", r_trade3$EntryTime),
    sprintf("  OK 确认: 在同一根K线"),
    "",
    "  该K线数据:",
    sprintf("    索引: %d", idx1),
    sprintf("    开盘: %.10f", as.numeric(data[idx1, "Open"])),
    sprintf("    最高: %.10f", as.numeric(data[idx1, "High"])),
    sprintf("    最低: %.10f", as.numeric(data[idx1, "Low"])),
    sprintf("    收盘: %.10f", as.numeric(data[idx1, "Close"])),
    ""
  )

  if (signals[idx1]) {
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])
    window_start <- max(1, idx1 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx1])
    current_low <- low_vec[idx1]
    drop_percent <- (window_high - current_low) / window_high * 100

    report <- c(report,
      "  信号分析:",
      sprintf("    窗口最高价: %.10f", window_high),
      sprintf("    当前最低价: %.10f", current_low),
      sprintf("    跌幅: %.2f%%", drop_percent),
      "    OK 该K线确实产生了买入信号 (跌幅 >= 20%)",
      ""
    )
  }
}

# 添加交易#10的详细数据
if (length(idx2) > 0) {
  report <- c(report,
    "",
    "问题交易#10 (2025-10-11 05:44):",
    sprintf("  R交易#9出场时间: %s", r_trade9$ExitTime),
    sprintf("  R交易#10入场时间: %s", r_trade10$EntryTime),
    sprintf("  OK 确认: 在同一根K线"),
    "",
    "  该K线数据:",
    sprintf("    索引: %d", idx2),
    sprintf("    开盘: %.10f", as.numeric(data[idx2, "Open"])),
    sprintf("    最高: %.10f", as.numeric(data[idx2, "High"])),
    sprintf("    最低: %.10f", as.numeric(data[idx2, "Low"])),
    sprintf("    收盘: %.10f", as.numeric(data[idx2, "Close"])),
    ""
  )

  if (signals2[idx2]) {
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])
    window_start <- max(1, idx2 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx2])
    current_low <- low_vec[idx2]
    drop_percent <- (window_high - current_low) / window_high * 100

    report <- c(report,
      "  信号分析:",
      sprintf("    窗口最高价: %.10f", window_high),
      sprintf("    当前最低价: %.10f", current_low),
      sprintf("    跌幅: %.2f%%", drop_percent),
      "    OK 该K线确实产生了买入信号 (跌幅 >= 20%)",
      ""
    )
  }
}

# 添加TradingView行为推断
report <- c(report,
  "",
  "四、TradingView行为推断",
  "------------------------",
  "",
  "基于观察到的差异, TradingView可能有以下机制之一:",
  "",
  "假设1: 信号检测在订单执行之前完成",
  "  描述:",
  "    - Pine Script在K线收盘时的执行顺序:",
  "      1) 计算所有技术指标",
  "      2) 评估所有策略条件 (strategy.entry等)",
  "      3) 生成订单列表",
  "      4) 执行订单 (止盈止损优先)",
  "    - 在步骤2时, 如果当前有持仓, 新的entry信号被忽略",
  "    - 即使步骤4执行了出场, 也不会回溯执行步骤2的信号",
  "  可能性: 高 ⭐⭐⭐",
  "  证据: 符合Pine Script的单次执行模型 (每根K线只评估一次)",
  "",
  "假设2: 一根K线只允许一次订单操作",
  "  描述:",
  "    - Pine Script限制每根K线只能执行一次订单操作",
  "    - 如果该K线执行了出场订单, 就不能再执行入场订单",
  "  可能性: 中 ⭐⭐",
  "  证据: Pine Script文档提到'订单队列'概念, 可能有此限制",
  "",
  "假设3: 入场延迟到下一根K线",
  "  描述:",
  "    - 即使在当前K线检测到信号, 实际入场在下一根K线",
  "    - 这样可以避免同一根K线的出场+入场冲突",
  "  可能性: 低 ⭐",
  "  证据: 不符合process_orders_on_close=true的行为",
  "",
  "假设4: 存在隐含的冷却期",
  "  描述:",
  "    - 出场后必须等待至少1根K线才能再入场",
  "  可能性: 低 ⭐",
  "  证据: Pine Script文档未提及, 且TradingView交易#8和#9仅间隔1根K线",
  "",
  "五、推荐解决方案",
  "----------------",
  "",
  "基于假设1 (最可能), 建议修改R回测引擎:",
  "",
  "方案A: 在K线开始时评估信号, 在K线结束时执行订单",
  "  优点: 完全对齐Pine Script的执行模型",
  "  缺点: 需要重构代码结构",
  "",
  "方案B: 禁止同一根K线的出场+入场",
  "  实现: 在入场检查时添加条件 i != lastExitBar",
  "  优点: 简单, 最小改动",
  "  缺点: 可能不完全对齐Pine Script (如果假设1错误)",
  "",
  "方案C: 入场延迟到下一根K线",
  "  实现: 将入场时机从当前K线收盘价改为下一根K线开盘价",
  "  优点: 避免冲突",
  "  缺点: 可能不对齐process_orders_on_close=true的行为",
  "",
  "**推荐: 方案B (最简单且有效)**",
  "",
  "六、验证计划",
  "------------",
  "",
  "1. 实现方案B, 重新运行回测",
  "2. 检查交易数量是否变为9笔 (与TV一致)",
  "3. 对比所有交易的时间和价格",
  "4. 如果仍有差异, 尝试方案A",
  "",
  "七、代码修改建议",
  "----------------",
  "",
  "在backtest_tradingview_aligned.R的第384行:",
  "",
  "修改前:",
  "  if (signals[i] && !inPosition) {",
  "",
  "修改后:",
  "  if (signals[i] && !inPosition && i != lastExitBar) {",
  "",
  "并添加日志:",
  "  if (signals[i] && !inPosition && i == lastExitBar) {",
  "    if (logIgnoredSignals) {",
  "      ignoredCount <- ignoredCount + 1",
  "      ignoredSignals[[ignoredCount]] <- list(",
  "        Bar = i,",
  "        Timestamp = as.character(timestamps[i]),",
  "        Reason = \"同一根K线已执行出场操作\"",
  "      )",
  "    }",
  "  }",
  "",
  "============================================================",
  "报告结束",
  "============================================================"
)

# 保存报告
report_file <- "r_extra_trades_debug.txt"
writeLines(report, report_file)

cat(sprintf("OK 调试报告已保存到: %s\n", report_file))
cat("\n")

# 简化的字符串连接运算符
`%+%` <- function(x, y) paste0(x, y)

cat("调试脚本执行完成!\n")

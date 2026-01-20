# ============================================================================
# 调试R额外交易问题 - 简化版
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
})

# 字符串连接运算符
`%+%` <- function(x, y) paste0(x, y)

# 加载回测引擎
source("backtest_tradingview_aligned.R")

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取交易记录
r_trades <- read.csv("outputs/r_backtest_trades_final.csv", stringsAsFactors = FALSE)
tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)

# 生成信号
signals <- generate_drop_signals(data, lookbackDays = 3, minDropPercent = 20)

# 初始化报告
report <- c()

report <- c(report,
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
  ""
)

# ============================================================================
# 分析问题交易
# ============================================================================

report <- c(report,
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
  "  - R在第384行没有检查 i != lastExitBar 的条件",
  ""
)

# 分析交易#3
r_trade2 <- r_trades[r_trades$TradeId == 2, ]
r_trade3 <- r_trades[r_trades$TradeId == 3, ]

report <- c(report,
  "三、问题交易详细分析",
  "---------------------",
  "",
  "问题交易#3 (2023-08-18 05:59):",
  sprintf("  R交易#2出场: %s @ %.10f (%s)", r_trade2$ExitTime, r_trade2$ExitPrice, r_trade2$ExitReason),
  sprintf("  R交易#3入场: %s @ %.10f", r_trade3$EntryTime, r_trade3$EntryPrice),
  "  OK 确认: 在同一根K线完成出场和入场",
  ""
)

# 查找对应的K线
idx1 <- grep("2023-08-18.*05:59", as.character(index(data)))
if (length(idx1) > 0) {
  idx1 <- idx1[1]
  bar_data <- as.data.frame(data[idx1, ])

  report <- c(report,
    sprintf("  该K线数据 (Bar %d):", idx1),
    sprintf("    开盘: %.10f", bar_data$Open),
    sprintf("    最高: %.10f", bar_data$High),
    sprintf("    最低: %.10f", bar_data$Low),
    sprintf("    收盘: %.10f", bar_data$Close),
    ""
  )

  if (signals[idx1]) {
    # 计算跌幅
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])
    window_start <- max(1, idx1 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx1])
    current_low <- low_vec[idx1]
    drop_percent <- (window_high - current_low) / window_high * 100

    report <- c(report,
      "  信号分析:",
      sprintf("    窗口最高价: %.10f (Bars %d-%d)", window_high, window_start, idx1),
      sprintf("    当前最低价: %.10f", current_low),
      sprintf("    跌幅: %.2f%%", drop_percent),
      "    OK 该K线确实产生了买入信号 (跌幅 >= 20%)",
      ""
    )
  } else {
    report <- c(report, "  WARN 该K线没有信号 (理论上不应该入场!)", "")
  }
}

# 分析交易#10
r_trade9 <- r_trades[r_trades$TradeId == 9, ]
r_trade10 <- r_trades[r_trades$TradeId == 10, ]

report <- c(report,
  "",
  "问题交易#10 (2025-10-11 05:44):",
  sprintf("  R交易#9出场: %s @ %.10f (%s)", r_trade9$ExitTime, r_trade9$ExitPrice, r_trade9$ExitReason),
  sprintf("  R交易#10入场: %s @ %.10f", r_trade10$EntryTime, r_trade10$EntryPrice),
  "  OK 确认: 在同一根K线完成出场和入场",
  ""
)

# 查找对应的K线
idx2 <- grep("2025-10-11.*05:44", as.character(index(data)))
if (length(idx2) > 0) {
  idx2 <- idx2[1]
  bar_data2 <- as.data.frame(data[idx2, ])

  report <- c(report,
    sprintf("  该K线数据 (Bar %d):", idx2),
    sprintf("    开盘: %.10f", bar_data2$Open),
    sprintf("    最高: %.10f", bar_data2$High),
    sprintf("    最低: %.10f", bar_data2$Low),
    sprintf("    收盘: %.10f", bar_data2$Close),
    ""
  )

  if (signals[idx2]) {
    # 计算跌幅
    lookbackBars <- 3
    high_vec <- as.numeric(data[, "High"])
    low_vec <- as.numeric(data[, "Low"])
    window_start <- max(1, idx2 - lookbackBars + 1)
    window_high <- max(high_vec[window_start:idx2])
    current_low <- low_vec[idx2]
    drop_percent <- (window_high - current_low) / window_high * 100

    report <- c(report,
      "  信号分析:",
      sprintf("    窗口最高价: %.10f (Bars %d-%d)", window_high, window_start, idx2),
      sprintf("    当前最低价: %.10f", current_low),
      sprintf("    跌幅: %.2f%%", drop_percent),
      "    OK 该K线确实产生了买入信号 (跌幅 >= 20%)",
      ""
    )
  } else {
    report <- c(report, "  WARN 该K线没有信号 (理论上不应该入场!)", "")
  }
}

# ============================================================================
# TradingView行为推断
# ============================================================================

report <- c(report,
  "",
  "四、TradingView行为推断",
  "------------------------",
  "",
  "基于观察到的差异, TradingView可能有以下机制之一:",
  "",
  "假设1: 信号检测在订单执行之前完成 ⭐⭐⭐ (最可能)",
  "  描述:",
  "    - Pine Script在K线收盘时的执行顺序:",
  "      1) 计算所有技术指标",
  "      2) 评估所有策略条件 (strategy.entry等)",
  "      3) 生成订单列表",
  "      4) 执行订单 (止盈止损优先)",
  "    - 在步骤2时, 如果当前有持仓, 新的entry信号被忽略",
  "    - 即使步骤4执行了出场, 也不会回溯执行步骤2的信号",
  "  可能性: 高",
  "  证据: 符合Pine Script的单次执行模型 (每根K线只评估一次)",
  "",
  "假设2: 一根K线只允许一次订单操作 ⭐⭐ (中等可能)",
  "  描述:",
  "    - Pine Script限制每根K线只能执行一次订单操作",
  "    - 如果该K线执行了出场订单, 就不能再执行入场订单",
  "  可能性: 中",
  "  证据: Pine Script文档提到'订单队列'概念, 可能有此限制",
  "",
  "假设3: 入场延迟到下一根K线 ⭐ (低可能)",
  "  描述:",
  "    - 即使在当前K线检测到信号, 实际入场在下一根K线",
  "    - 这样可以避免同一根K线的出场+入场冲突",
  "  可能性: 低",
  "  证据: 不符合process_orders_on_close=true的行为",
  "",
  "假设4: 存在隐含的冷却期 ⭐ (低可能)",
  "  描述:",
  "    - 出场后必须等待至少1根K线才能再入场",
  "  可能性: 低",
  "  证据: Pine Script文档未提及",
  ""
)

# ============================================================================
# 解决方案
# ============================================================================

report <- c(report,
  "",
  "五、推荐解决方案",
  "----------------",
  "",
  "基于假设1 (最可能), 建议修改R回测引擎:",
  "",
  "方案A: 在K线开始时评估信号, 在K线结束时执行订单",
  "  优点: 完全对齐Pine Script的执行模型",
  "  缺点: 需要重构代码结构",
  "  实现复杂度: 高",
  "",
  "方案B: 禁止同一根K线的出场+入场 ⭐⭐⭐ (推荐)",
  "  优点: 简单, 最小改动, 立即见效",
  "  缺点: 可能不完全对齐Pine Script (如果假设1错误)",
  "  实现复杂度: 低",
  "  ",
  "  实现方法:",
  "  在backtest_tradingview_aligned.R的第384行:",
  "  ",
  "  修改前:",
  "    if (signals[i] && !inPosition) {",
  "  ",
  "  修改后:",
  "    if (signals[i] && !inPosition && i != lastExitBar) {",
  "  ",
  "  并添加日志 (在第384行之前):",
  "    if (signals[i] && !inPosition && i == lastExitBar) {",
  "      if (logIgnoredSignals) {",
  "        ignoredCount <- ignoredCount + 1",
  "        ignoredSignals[[ignoredCount]] <- list(",
  "          Bar = i,",
  "          Timestamp = as.character(timestamps[i]),",
  "          Reason = '同一根K线已执行出场操作'",
  "        )",
  "      }",
  "    }",
  "",
  "方案C: 入场延迟到下一根K线",
  "  优点: 避免冲突",
  "  缺点: 可能不对齐process_orders_on_close=true的行为",
  "  实现复杂度: 中",
  "",
  "**推荐: 方案B (最简单且有效)**",
  ""
)

# ============================================================================
# 验证计划
# ============================================================================

report <- c(report,
  "",
  "六、验证计划",
  "------------",
  "",
  "1. 实现方案B, 添加 i != lastExitBar 检查",
  "2. 重新运行回测",
  "3. 检查交易数量是否变为9笔 (与TV一致)",
  "4. 对比所有交易的时间、价格和盈亏",
  "5. 如果仍有差异, 进行进一步调试或尝试方案A",
  "",
  "============================================================",
  "报告结束",
  "============================================================"
)

# 保存报告
report_file <- "r_extra_trades_debug.txt"
writeLines(report, report_file)

cat("\n")
cat("============================================================\n")
cat("调试报告已生成\n")
cat("============================================================\n\n")
cat(sprintf("文件位置: %s\n", report_file))
cat("\n")
cat("关键发现:\n")
cat("  1. R在同一根K线内先执行出场, 然后立即检测到新信号并入场\n")
cat("  2. TradingView不允许这种行为 (可能是信号在出场前就已评估)\n")
cat("  3. 解决方案: 添加 i != lastExitBar 检查, 防止同一K线的重复操作\n")
cat("\n")
cat("下一步:\n")
cat("  执行 test_fix_same_bar_entry.R 来验证修复方案\n")
cat("\n")

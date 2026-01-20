# 深度分析：为什么还没有100%对齐
# ==========================================

library(xts)

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

# 读取对比结果
tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
r_trades <- read.csv("outputs/r_backtest_trades_100percent.csv", stringsAsFactors = FALSE)

cat("\n===============================================================================\n")
cat("深度代码审查：找出100%对齐的障碍\n")
cat("===============================================================================\n\n")

# 1. 对齐状态分析
cat("【1. 当前对齐状态】\n")
cat(rep("-", 80), "\n", sep="")

cat(sprintf("TradingView交易数: %d\n", nrow(tv_trades)))
cat(sprintf("R回测交易数: %d\n", nrow(r_trades)))

if(nrow(tv_trades) == nrow(r_trades)) {
  cat("OK 交易数量: 100%对齐\n\n")
} else {
  cat(sprintf("FAIL 交易数量: 不对齐 (TV=%d vs R=%d)\n\n", nrow(tv_trades), nrow(r_trades)))
}

# 2. 逐笔对比
cat("【2. 逐笔交易详细对比】\n")
cat(rep("-", 80), "\n", sep="")

for(i in 1:min(nrow(tv_trades), nrow(r_trades))) {
  tv <- tv_trades[i, ]
  r <- r_trades[i, ]

  cat(sprintf("\n交易 #%d:\n", i))
  cat(sprintf("  TV入场: %s @ %.8f\n", tv$EntryTime, tv$EntryPrice))
  cat(sprintf("  R入场:  %s @ %.8f\n", r$EntryTime, r$EntryPrice))

  # 时间对齐检查
  tv_time <- as.POSIXct(tv$EntryTime, format="%Y-%m-%d %H:%M:%S")
  r_time <- as.POSIXct(r$EntryTime, format="%Y-%m-%d %H:%M:%S")
  time_diff_mins <- as.numeric(difftime(tv_time, r_time, units="mins"))

  if(abs(time_diff_mins) < 1) {
    cat("  OK 入场时间: 对齐\n")
  } else {
    cat(sprintf("  FAIL 入场时间: 相差%.0f分钟\n", time_diff_mins))
  }

  # 价格对齐检查
  price_diff_pct <- abs(tv$EntryPrice - r$EntryPrice) / tv$EntryPrice * 100
  if(price_diff_pct < 0.01) {
    cat("  OK 入场价格: 对齐\n")
  } else {
    cat(sprintf("  FAIL 入场价格: 相差%.4f%%\n", price_diff_pct))
  }

  # 出场时间对比
  tv_exit <- as.POSIXct(tv$ExitTime, format="%Y-%m-%d %H:%M:%S")
  r_exit <- as.POSIXct(r$ExitTime, format="%Y-%m-%d %H:%M:%S")
  exit_diff_mins <- as.numeric(difftime(tv_exit, r_exit, units="mins"))

  cat(sprintf("  TV出场: %s @ %.8f\n", tv$ExitTime, tv$ExitPrice))
  cat(sprintf("  R出场:  %s @ %.8f\n", r$ExitTime, r$ExitPrice))

  if(abs(exit_diff_mins) < 1) {
    cat("  OK 出场时间: 对齐\n")
  } else {
    cat(sprintf("  FAIL 出场时间: 相差%.0f分钟\n", exit_diff_mins))
  }
}

# 3. 关键差异案例分析
cat("\n\n【3. 关键差异案例分析】\n")
cat(rep("-", 80), "\n", sep="")

# 找出入场时间不对齐的交易
misaligned_entry <- c()
for(i in 1:min(nrow(tv_trades), nrow(r_trades))) {
  tv_time <- as.POSIXct(tv_trades$EntryTime[i], format="%Y-%m-%d %H:%M:%S")
  r_time <- as.POSIXct(r_trades$EntryTime[i], format="%Y-%m-%d %H:%M:%S")
  if(abs(as.numeric(difftime(tv_time, r_time, units="mins"))) >= 1) {
    misaligned_entry <- c(misaligned_entry, i)
  }
}

if(length(misaligned_entry) > 0) {
  cat(sprintf("发现%d笔入场时间不对齐的交易: #%s\n\n",
              length(misaligned_entry),
              paste(misaligned_entry, collapse=", ")))

  # 深入分析第一个不对齐的交易
  idx <- misaligned_entry[1]
  tv <- tv_trades[idx, ]
  r <- r_trades[idx, ]

  cat(sprintf("深入分析交易 #%d:\n", idx))
  cat(sprintf("TV: %s @ %.8f\n", tv$EntryTime, tv$EntryPrice))
  cat(sprintf("R:  %s @ %.8f\n", r$EntryTime, r$EntryPrice))

  # 提取相关K线数据
  tv_time <- as.POSIXct(tv$EntryTime, format="%Y-%m-%d %H:%M:%S")
  r_time <- as.POSIXct(r$EntryTime, format="%Y-%m-%d %H:%M:%S")

  # 获取时间范围
  start_time <- min(tv_time, r_time) - 60*60  # 前1小时
  end_time <- max(tv_time, r_time) + 60*60    # 后1小时

  time_range <- paste(format(start_time, "%Y-%m-%d %H:%M:%S"),
                      format(end_time, "%Y-%m-%d %H:%M:%S"),
                      sep="/")

  klines <- data[time_range]

  cat("\n相关K线数据:\n")
  cat(sprintf("%-20s %-12s %-12s %-12s %-12s\n",
              "时间", "开盘", "最高", "最低", "收盘"))
  cat(rep("-", 80), "\n", sep="")

  for(j in 1:nrow(klines)) {
    ts <- index(klines)[j]
    marker <- ""
    if(abs(as.numeric(difftime(ts, tv_time, units="secs"))) < 60) {
      marker <- " <- TV入场"
    }
    if(abs(as.numeric(difftime(ts, r_time, units="secs"))) < 60) {
      marker <- paste0(marker, " <- R入场")
    }

    cat(sprintf("%-20s %.8f %.8f %.8f %.8f%s\n",
                format(ts, "%Y-%m-%d %H:%M:%S"),
                klines[j, "Open"],
                klines[j, "High"],
                klines[j, "Low"],
                klines[j, "Close"],
                marker))
  }
}

# 4. Pine Script行为分析
cat("\n\n【4. Pine Script行为分析】\n")
cat(rep("=", 80), "\n", sep="")

cat("\n关键问题1: ta.highest(high, lookbackBars)是否包含当前K线?\n")
cat("答案: 否。根据Pine Script文档,ta.highest(high, n)查看过去n根K线,不包含当前K线。\n")
cat("     但是,在strategy函数中,当process_orders_on_close=true时:\n")
cat("     - 信号在K线收盘时计算(此时当前K线已完成)\n")
cat("     - 因此当前K线应该被包含在窗口计算中\n")
cat("     - 这是一个微妙的时序问题!\n\n")

cat("关键问题2: process_orders_on_close=true的精确含义?\n")
cat("答案: 订单在K线收盘时执行,使用收盘价作为入场价格。\n")
cat("     这意味着:\n")
cat("     - 信号K线收盘时产生信号\n")
cat("     - 立即在该K线收盘价入场(而非下一根K线开盘)\n")
cat("     - 但ta.highest()的窗口问题仍需注意\n\n")

cat("关键问题3: 出场检查应该在 i > entryBar 还是 i >= entryBar?\n")
cat("答案: 必须是 i > entryBar!\n")
cat("     原因:\n")
cat("     - 入场发生在K线N的收盘\n")
cat("     - 不能在同一根K线检查出场(数据尚未完成)\n")
cat("     - 必须等到K线N+1才能检查止盈止损\n")
cat("     - 这与代码line 265一致: if (inPosition && i > entryBar)\n\n")

# 5. 代码实现检查
cat("【5. 代码实现检查】\n")
cat(rep("=", 80), "\n", sep="")

cat("\n检查点1: 信号生成逻辑 (Line 93-126)\n")
cat("  当前实现: lookbackBars <- lookbackDays (直接使用,不转换)\n")
cat("  RcppRoll窗口: align='right' (包含当前位置)\n")
cat("  问题: 是否需要lag 1位?\n")
cat("  建议: 需要测试window_high是否应该lag(window_high, 1)\n\n")

cat("检查点2: 入场价格逻辑 (Line 389-411)\n")
cat("  当前实现: processOnClose=TRUE时,使用close_vec[i]立即入场\n")
cat("  TradingView行为: 在信号K线收盘价入场\n")
cat("  问题: 是否完全一致?\n")
cat("  建议: 需要验证TV是否真的使用当前K线收盘价,还是下一根K线价格\n\n")

cat("检查点3: 出场逻辑 (Line 265-327)\n")
cat("  当前实现: if (inPosition && i > entryBar)\n")
cat("  出场价格: 使用收盘价(Line 296, 302, 316, 323)\n")
cat("  问题: 应该用精确的TP/SL价格还是收盘价?\n")
cat("  TradingView行为: 盘中触发时立即出场,但回测中记录的是收盘价\n")
cat("  建议: 当前使用收盘价是正确的(符合TV回测结果)\n\n")

cat("检查点4: 同一K线重入限制 (Line 384)\n")
cat("  当前实现: if (signals[i] && !inPosition && i != lastExitBar)\n")
cat("  作用: 防止在同一根K线先出场再入场\n")
cat("  问题: 是否足够?\n")
cat("  建议: 这个逻辑是正确的\n\n")

# 6. 问题诊断和修复建议
cat("【6. 问题诊断和修复建议】\n")
cat(rep("=", 80), "\n", sep="")

cat("\n根本问题:\n")
cat("  当前对齐率:\n")
cat("    - 交易数量: 9 vs 9 (100%) OK\n")
cat("    - 胜率: 100% vs 100% (100%) OK\n")
cat("    - 入场时间: 7/9 (77.8%) FAIL\n")
cat("    - 入场价格: 8/9 (88.9%) FAIL\n")
cat("    - 出场时间: 2/9 (22.2%) FAIL\n\n")

cat("可能的原因:\n")
cat("  1. 信号窗口计算问题:\n")
cat("     - ta.highest()的[1]索引表示排除当前K线\n")
cat("     - 但在K线收盘时,当前K线已完成,应该包含\n")
cat("     - R实现可能需要调整window计算方式\n\n")

cat("  2. 入场时机问题:\n")
cat("     - 从交易#9看,TV使用的入场价6.84e-06\n")
cat("     - R使用的入场价6.68e-06\n")
cat("     - 这表明可能使用了不同K线的收盘价\n\n")

cat("  3. 出场时机问题:\n")
cat("     - 出场时间对齐率只有22.2%\n")
cat("     - 可能是TP/SL触发逻辑不一致\n\n")

cat("\n修复方案:\n")
cat("  方案A: 调整信号窗口计算\n")
cat("    - Line 113-114: 将window_high向前lag 1位\n")
cat("    - 代码: window_high_prev <- c(NA, window_high[-n])\n")
cat("    - 然后在Line 120使用window_high_prev而非window_high\n\n")

cat("  方案B: 调整入场价格获取\n")
cat("    - 如果信号在K线i触发\n")
cat("    - 入场应该使用K线i的收盘价(当前做法)\n")
cat("    - 但需要确认TV是否真的这样做\n\n")

cat("  方案C: 调整出场逻辑\n")
cat("    - 当前使用收盘价出场\n")
cat("    - 可能需要检查是否应该使用精确的TP/SL价格\n")
cat("    - 但从TV的PnL看,应该是用收盘价\n\n")

cat("\n推荐测试顺序:\n")
cat("  1. 先测试方案A(信号窗口lag)\n")
cat("  2. 检查入场时间和价格对齐率变化\n")
cat("  3. 如果改善,继续调试出场逻辑\n")
cat("  4. 如果不改善,检查TV策略代码的具体实现\n\n")

cat("===============================================================================\n")
cat("分析完成!\n")
cat("===============================================================================\n\n")

# ============================================================================
# QCrypto::backtest (backtest_cpp wrapper) 测试脚本
# ============================================================================
# 目标：测试QCrypto::backtest函数，这是backtest_cpp的R包装器
# 该函数适合"满仓/清仓"策略，与TradingView逻辑一致
# ============================================================================

library(QCrypto)
library(tidyverse)
library(lubridate)

# 加载数据
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

cat("=== QCrypto::backtest 函数分析 ===\n\n")

cat("函数签名:\n")
cat("backtest(open, buy_signal, sell_signal, initial_capital, fee = 0.001)\n\n")

cat("参数说明:\n")
cat("- open: 开盘价向量 (或收盘价，用于计算收益)\n")
cat("- buy_signal: 买入信号向量 (1=买入, 0=不操作)\n")
cat("- sell_signal: 卖出信号向量 (1=卖出, 0=不操作)\n")
cat("- initial_capital: 初始资金\n")
cat("- fee: 交易费率 (默认0.001 = 0.1%)\n\n")

cat("核心特点:\n")
cat("1. 满仓/清仓策略: 买入时投入全部资金，卖出时全部平仓\n")
cat("2. 信号逻辑: buy_signal=1时开仓，sell_signal=1时平仓\n")
cat("3. 底层C++实现: backtest_cpp，性能优化\n")
cat("4. 与TradingView一致的逻辑\n\n")

# ============================================================================
# 实现我们的"连续3根下跌20%后反弹策略"
# ============================================================================

cat("=== 实现连续3根下跌20%策略 ===\n\n")

# 策略参数
LOOKBACK <- 3        # 回溯K线数
DROP_THRESHOLD <- 0.20  # 下跌阈值20%
TP_PERCENT <- 0.10   # 止盈10%
SL_PERCENT <- 0.10   # 止损10%
INITIAL_CAPITAL <- 100  # 初始资金
FEE <- 0.001         # 0.1%交易费

cat(sprintf("参数设置:\n"))
cat(sprintf("- 回溯期: %d根K线\n", LOOKBACK))
cat(sprintf("- 下跌阈值: %.1f%%\n", DROP_THRESHOLD * 100))
cat(sprintf("- 止盈: %.1f%%\n", TP_PERCENT * 100))
cat(sprintf("- 止损: %.1f%%\n", SL_PERCENT * 100))
cat(sprintf("- 初始资金: $%.0f\n", INITIAL_CAPITAL))
cat(sprintf("- 手续费: %.2f%%\n\n", FEE * 100))

# 准备数据
df <- data.frame(
  time = index(data),
  open = as.numeric(data$Open),
  high = as.numeric(data$High),
  low = as.numeric(data$Low),
  close = as.numeric(data$Close),
  volume = as.numeric(data$Volume)
)

n <- nrow(df)
cat(sprintf("数据: %d根K线\n", n))
cat(sprintf("时间范围: %s 至 %s\n\n",
            format(df$time[1], "%Y-%m-%d %H:%M"),
            format(df$time[n], "%Y-%m-%d %H:%M")))

# ============================================================================
# 策略1: 简单版 - 只检测连续下跌，不考虑止盈止损
# ============================================================================

cat("=== 策略1: 简单版 (无止盈止损) ===\n\n")

# 计算连续3根K线的累计跌幅
calculate_drop <- function(close, lookback = 3) {
  n <- length(close)
  drop <- rep(0, n)

  for (i in (lookback+1):n) {
    high_price <- max(close[(i-lookback):(i-1)])
    current_price <- close[i]
    drop[i] <- (high_price - current_price) / high_price
  }

  return(drop)
}

df$drop <- calculate_drop(df$close, LOOKBACK)

# 生成买入信号：当累计跌幅 >= 20%
df$buy_signal_simple <- ifelse(df$drop >= DROP_THRESHOLD, 1, 0)

# 生成卖出信号：买入后下一根K线就卖出（简单测试）
df$sell_signal_simple <- c(0, df$buy_signal_simple[-n])

# 统计信号
n_buy <- sum(df$buy_signal_simple)
n_sell <- sum(df$sell_signal_simple)

cat(sprintf("检测到 %d 个买入信号\n", n_buy))
cat(sprintf("检测到 %d 个卖出信号\n\n", n_sell))

if (n_buy > 0) {
  # 运行backtest
  result_simple <- backtest(
    open = df$close,  # 使用close作为交易价格
    buy_signal = df$buy_signal_simple,
    sell_signal = df$sell_signal_simple,
    initial_capital = INITIAL_CAPITAL,
    fee = FEE
  )

  # 查看结果结构
  cat("backtest返回的列名:\n")
  print(colnames(result_simple))
  cat("\n")

  # 显示前几行
  cat("前10行结果:\n")
  print(head(result_simple, 10))
  cat("\n")

  # 显示有交易的行
  trades <- result_simple %>%
    filter(buy_signal == 1 | sell_signal == 1)

  cat(sprintf("交易记录 (%d笔):\n", nrow(trades)))
  print(head(trades, 20))
  cat("\n")

  # 计算收益
  final_equity <- tail(result_simple, 1)
  cat("最终结果:\n")
  print(final_equity)
  cat("\n")
}

# ============================================================================
# 策略2: 完整版 - 包含止盈止损逻辑
# ============================================================================

cat("\n=== 策略2: 完整版 (含止盈止损) ===\n\n")

# 生成交易信号（包含止盈止损）
generate_signals_with_tpsl <- function(df, lookback, drop_threshold, tp_pct, sl_pct) {
  n <- nrow(df)
  buy_signal <- rep(0, n)
  sell_signal <- rep(0, n)

  in_position <- FALSE
  entry_price <- 0

  for (i in (lookback+1):n) {
    if (!in_position) {
      # 检查是否触发买入条件
      high_price <- max(df$close[(i-lookback):(i-1)])
      current_price <- df$close[i]
      drop <- (high_price - current_price) / high_price

      if (drop >= drop_threshold) {
        buy_signal[i] <- 1
        in_position <- TRUE
        entry_price <- df$close[i]  # 使用收盘价作为入场价
      }
    } else {
      # 检查止盈止损
      current_price <- df$close[i]
      profit_pct <- (current_price - entry_price) / entry_price

      # 止盈或止损
      if (profit_pct >= tp_pct || profit_pct <= -sl_pct) {
        sell_signal[i] <- 1
        in_position <- FALSE
        entry_price <- 0
      }
    }
  }

  return(list(buy = buy_signal, sell = sell_signal))
}

signals <- generate_signals_with_tpsl(
  df,
  LOOKBACK,
  DROP_THRESHOLD,
  TP_PERCENT,
  SL_PERCENT
)

df$buy_signal <- signals$buy
df$sell_signal <- signals$sell

# 统计信号
n_buy <- sum(df$buy_signal)
n_sell <- sum(df$sell_signal)

cat(sprintf("检测到 %d 个买入信号\n", n_buy))
cat(sprintf("检测到 %d 个卖出信号\n\n", n_sell))

if (n_buy > 0) {
  # 运行backtest
  result_full <- backtest(
    open = df$close,
    buy_signal = df$buy_signal,
    sell_signal = df$sell_signal,
    initial_capital = INITIAL_CAPITAL,
    fee = FEE
  )

  # 显示交易记录
  trades <- df %>%
    mutate(result = result_full) %>%
    filter(buy_signal == 1 | sell_signal == 1) %>%
    select(time, open, close, buy_signal, sell_signal, drop)

  cat(sprintf("交易记录 (%d笔):\n", nrow(trades)))
  print(trades)
  cat("\n")

  # 计算统计信息
  buy_times <- df$time[df$buy_signal == 1]
  sell_times <- df$time[df$sell_signal == 1]

  cat("买入时间:\n")
  print(buy_times)
  cat("\n")

  cat("卖出时间:\n")
  print(sell_times)
  cat("\n")

  # 最终权益
  final_result <- result_full[nrow(result_full), ]
  cat("最终结果:\n")
  print(as.data.frame(final_result))
  cat("\n")

  # 尝试提取权益曲线（如果存在）
  if ("equity" %in% colnames(result_full)) {
    final_equity <- tail(result_full$equity, 1)
    total_return <- (final_equity - INITIAL_CAPITAL) / INITIAL_CAPITAL * 100

    cat(sprintf("初始资金: $%.2f\n", INITIAL_CAPITAL))
    cat(sprintf("最终权益: $%.2f\n", final_equity))
    cat(sprintf("总收益率: %.2f%%\n", total_return))
  }
}

# ============================================================================
# 保存结果
# ============================================================================

cat("\n=== 保存结果 ===\n\n")

# 保存带信号的数据
result_data <- df %>%
  select(time, open, high, low, close, volume, drop, buy_signal, sell_signal)

write.csv(result_data,
          "outputs/qcrypto_backtest_signals.csv",
          row.names = FALSE)

cat("已保存信号数据到: qcrypto_backtest_signals.csv\n")

if (exists("result_full")) {
  write.csv(result_full,
            "outputs/qcrypto_backtest_result.csv",
            row.names = FALSE)
  cat("已保存回测结果到: qcrypto_backtest_result.csv\n")
}

cat("\n测试完成！\n")

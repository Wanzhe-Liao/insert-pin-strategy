# 从索引85360入场后分析止损触发
# 对比R的止损逻辑和可能的TradingView行为差异

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

entry_idx <- 85360
entry_price <- 0.00000684
stop_loss_price <- entry_price * 0.90  # 10% 止损
take_profit_price <- entry_price * 1.10  # 10% 止盈

cat('\n================================================================================\n')
cat('从索引85360入场后的止盈止损分析\n')
cat('================================================================================\n\n')

cat(sprintf('入场索引: %d\n', entry_idx))
cat(sprintf('入场时间: %s\n', as.character(index(data)[entry_idx])))
cat(sprintf('入场价格: $%.8f\n', entry_price))
cat(sprintf('止损价格: $%.8f (-10%%)\n', stop_loss_price))
cat(sprintf('止盈价格: $%.8f (+10%%)\n\n', take_profit_price))

cat(sprintf('%-6s %-30s %12s %12s %12s %12s %s %s\n',
            '索引', '时间', 'Open', 'High', 'Low', 'Close', 'SL?', 'TP?'))
cat(paste(rep('-', 120), collapse=''), '\n')

# 检查后续50根K线
sl_triggered_idx <- NA
tp_triggered_idx <- NA

for (i in (entry_idx + 1):(entry_idx + 50)) {
  if (i > nrow(data)) break

  time_val <- as.character(index(data)[i])
  open_val <- as.numeric(data$Open[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])
  close_val <- as.numeric(data$Close[i])

  sl_hit <- low_val <= stop_loss_price
  tp_hit <- high_val >= take_profit_price

  sl_str <- ifelse(sl_hit, 'OK SL', '  -')
  tp_str <- ifelse(tp_hit, 'OK TP', '  -')

  cat(sprintf('%-6d %-30s %12.8f %12.8f %12.8f %12.8f %s %s',
              i, time_val, open_val, high_val, low_val, close_val, sl_str, tp_str))

  if (sl_hit && is.na(sl_triggered_idx)) {
    sl_triggered_idx <- i
    cat(sprintf(' ← R在此止损出场 @ $%.8f', close_val))
  }

  if (tp_hit && is.na(tp_triggered_idx)) {
    tp_triggered_idx <- i
    cat(sprintf(' ← 止盈触发 @ $%.8f', close_val))
  }

  cat('\n')

  # 如果两者都触发了，停止
  if (!is.na(sl_triggered_idx) && !is.na(tp_triggered_idx)) {
    break
  }
}

cat('\n')
cat('================================================================================\n')
cat('结论分析\n')
cat('================================================================================\n\n')

if (!is.na(sl_triggered_idx)) {
  sl_time <- as.character(index(data)[sl_triggered_idx])
  sl_close <- as.numeric(data$Close[sl_triggered_idx])
  sl_pnl <- (sl_close - entry_price) / entry_price * 100

  cat(sprintf('OK R的止损触发:\n'))
  cat(sprintf('   索引: %d\n', sl_triggered_idx))
  cat(sprintf('   时间: %s\n', sl_time))
  cat(sprintf('   Low:  $%.8f (触及SL $%.8f)\n',
              as.numeric(data$Low[sl_triggered_idx]), stop_loss_price))
  cat(sprintf('   出场价格: $%.8f (Close)\n', sl_close))
  cat(sprintf('   盈亏: %.2f%%\n\n', sl_pnl))
}

if (!is.na(tp_triggered_idx)) {
  tp_time <- as.character(index(data)[tp_triggered_idx])
  tp_close <- as.numeric(data$Close[tp_triggered_idx])
  tp_pnl <- (tp_close - entry_price) / entry_price * 100

  cat(sprintf('OK 止盈触发:\n'))
  cat(sprintf('   索引: %d\n', tp_triggered_idx))
  cat(sprintf('   时间: %s\n', tp_time))
  cat(sprintf('   High: $%.8f (触及TP $%.8f)\n',
              as.numeric(data$High[tp_triggered_idx]), take_profit_price))
  cat(sprintf('   出场价格: $%.8f (Close)\n', tp_close))
  cat(sprintf('   盈亏: %.2f%%\n\n', tp_pnl))
}

cat('TradingView记录:\n')
cat('  入场: 2025-10-11 05:44:59 @ $0.00000684\n')
cat('  出场: 2025-10-13 02:15:00 @ $0.00000753 (止盈)\n')
cat('  盈亏: 9.92%\n\n')

cat('对比:\n')
if (!is.na(sl_triggered_idx)) {
  cat(sprintf('FAIL R在 %s 止损出场 (%.2f%%)\n', sl_time, sl_pnl))
  cat('OK TradingView在 2025-10-13 02:15 止盈出场 (9.92%)\n\n')

  cat('💡 可能原因:\n')
  cat('   1. TradingView入场的K线与R不同（虽然价格相同）\n')
  cat('   2. TradingView的数据源有不同的High/Low值\n')
  cat('   3. TradingView的止损计算方式不同\n')
  cat('   4. TradingView使用不同的订单执行逻辑\n')
}

cat('\n完成!\n\n')

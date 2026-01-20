# 检查2025-10-11 06:14是否真的触发了止损
# 验证R的止损逻辑是否正确

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('检查交易#10的止损触发情况\n')
cat('================================================================================\n\n')

# 入场信息
entry_time <- as.POSIXct('2025-10-11 05:59:59.999', tz='UTC')
entry_price <- 0.00000684
stop_loss_price <- entry_price * 0.90  # 10% 止损

cat(sprintf('入场时间: %s\n', as.character(entry_time)))
cat(sprintf('入场价格: $%.8f\n', entry_price))
cat(sprintf('止损价格: $%.8f (10%% 止损)\n', stop_loss_price))
cat('\n')

# 查找入场后的K线
entry_idx <- which(abs(as.numeric(difftime(index(data), entry_time, units='secs'))) < 1)

if (length(entry_idx) == 0) {
  cat('FAIL 未找到入场K线\n')
  quit()
}

entry_idx <- entry_idx[1]
cat(sprintf('入场K线索引: %d\n', entry_idx))
cat(sprintf('入场K线时间: %s\n', as.character(index(data)[entry_idx])))
cat('\n')

# 检查后续5根K线
cat('================================================================================\n')
cat('入场后的K线数据（检查止损触发）\n')
cat('================================================================================\n\n')

cat(sprintf('%-25s %12s %12s %12s %12s %10s\n',
            '时间', 'Open', 'High', 'Low', 'Close', '触发止损?'))
cat(paste(rep('-', 100), collapse=''), '\n')

for (i in entry_idx:(entry_idx + 5)) {
  if (i > nrow(data)) break

  time_val <- as.character(index(data)[i])
  open_val <- as.numeric(data$Open[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])
  close_val <- as.numeric(data$Close[i])

  # 检查是否触发止损（Low价格低于或等于止损价格）
  sl_triggered <- low_val <= stop_loss_price

  cat(sprintf('%-25s %12.8f %12.8f %12.8f %12.8f %10s\n',
              time_val, open_val, high_val, low_val, close_val,
              ifelse(sl_triggered, 'OK 是', 'FAIL 否')))

  if (sl_triggered) {
    cat('\n')
    cat(sprintf('>>> 止损在此K线触发: %s\n', time_val))
    cat(sprintf('    Low价格: $%.8f\n', low_val))
    cat(sprintf('    止损价格: $%.8f\n', stop_loss_price))
    cat(sprintf('    差异: $%.10f (%.3f%%)\n',
                stop_loss_price - low_val,
                (stop_loss_price - low_val) / stop_loss_price * 100))
    cat('\n')
  }
}

cat('\n')

# 重点检查06:14那根K线
check_time <- as.POSIXct('2025-10-11 06:14:59.999', tz='UTC')
check_idx <- which(abs(as.numeric(difftime(index(data), check_time, units='secs'))) < 1)

if (length(check_idx) > 0) {
  check_idx <- check_idx[1]

  cat('================================================================================\n')
  cat('06:14 K线详细信息\n')
  cat('================================================================================\n\n')

  cat(sprintf('时间: %s\n', as.character(index(data)[check_idx])))
  cat(sprintf('Open:  $%.8f\n', as.numeric(data$Open[check_idx])))
  cat(sprintf('High:  $%.8f\n', as.numeric(data$High[check_idx])))
  cat(sprintf('Low:   $%.8f\n', as.numeric(data$Low[check_idx])))
  cat(sprintf('Close: $%.8f\n', as.numeric(data$Close[check_idx])))
  cat('\n')

  low_val <- as.numeric(data$Low[check_idx])
  close_val <- as.numeric(data$Close[check_idx])

  cat(sprintf('止损价格: $%.8f\n', stop_loss_price))
  cat(sprintf('Low vs SL: $%.8f %s $%.8f (差异 %.3f%%)\n',
              low_val,
              ifelse(low_val <= stop_loss_price, '<=', '>'),
              stop_loss_price,
              abs(low_val - stop_loss_price) / stop_loss_price * 100))

  if (low_val <= stop_loss_price) {
    cat('\nOK 止损在06:14被触发（Low价格触及止损线）\n')
    cat(sprintf('   执行价格（Close）: $%.8f\n', close_val))
    cat(sprintf('   盈亏: %.2f%%\n', (close_val - entry_price) / entry_price * 100))
  } else {
    cat('\nFAIL 止损在06:14未被触发（Low价格未触及止损线）\n')
    cat('   这可能解释了为什么TradingView没有在此处出场\n')
  }
}

cat('\n完成!\n\n')

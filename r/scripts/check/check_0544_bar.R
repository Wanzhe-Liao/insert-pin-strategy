# 检查TradingView显示的入场时间05:44:59那根K线
# 查看它的收盘价是否真的是$0.00000684

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('检查05:44:59那根K线\n')
cat('================================================================================\n\n')

# 查找05:44:59附近的K线
target_time_str <- '2025-10-11 05:44:59'

# 搜索范围：05:30 到 06:00
start_time <- as.POSIXct('2025-10-11 05:30:00', tz='UTC')
end_time <- as.POSIXct('2025-10-11 06:00:00', tz='UTC')

time_indices <- which(index(data) >= start_time & index(data) <= end_time)

cat(sprintf('05:30-06:00之间的K线数据:\n'))
cat(sprintf('%-25s %12s %12s %12s %12s\n',
            '时间', 'Open', 'High', 'Low', 'Close'))
cat(paste(rep('-', 100), collapse=''), '\n')

for (i in time_indices) {
  time_val <- as.character(index(data)[i])
  open_val <- as.numeric(data$Open[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])
  close_val <- as.numeric(data$Close[i])

  marker <- ''
  if (grepl('05:44', time_val)) marker <- ' ← TradingView入场时间'
  if (close_val == 0.00000684) marker <- paste(marker, '← Close=$0.00000684')

  cat(sprintf('%-25s %12.8f %12.8f %12.8f %12.8f%s\n',
              time_val, open_val, high_val, low_val, close_val, marker))
}

cat('\n')

# 精确查找05:44:59
exact_indices <- which(grepl('05:44:59', as.character(index(data))))

if (length(exact_indices) > 0) {
  cat('================================================================================\n')
  cat('05:44:59 K线详细信息\n')
  cat('================================================================================\n\n')

  for (idx in exact_indices) {
    cat(sprintf('索引: %d\n', idx))
    cat(sprintf('时间: %s\n', as.character(index(data)[idx])))
    cat(sprintf('Open:  $%.8f\n', as.numeric(data$Open[idx])))
    cat(sprintf('High:  $%.8f\n', as.numeric(data$High[idx])))
    cat(sprintf('Low:   $%.8f\n', as.numeric(data$Low[idx])))
    cat(sprintf('Close: $%.8f\n', as.numeric(data$Close[idx])))

    close_val <- as.numeric(data$Close[idx])
    if (abs(close_val - 0.00000684) < 1e-10) {
      cat('\nOK Close价格匹配 $0.00000684\n')
    } else {
      cat(sprintf('\nFAIL Close价格不匹配: $%.8f vs $0.00000684 (差异 $%.10f)\n',
                  close_val, abs(close_val - 0.00000684)))
    }

    # 检查后续K线的止损触发
    cat('\n后续K线:\n')
    cat(sprintf('%-25s %12s %12s %12s %12s %10s\n',
                '时间', 'Open', 'High', 'Low', 'Close', '触发止损?'))
    cat(paste(rep('-', 100), collapse=''), '\n')

    entry_price <- close_val
    stop_loss_price <- entry_price * 0.90

    for (j in (idx + 1):(idx + 5)) {
      if (j > nrow(data)) break

      time_j <- as.character(index(data)[j])
      open_j <- as.numeric(data$Open[j])
      high_j <- as.numeric(data$High[j])
      low_j <- as.numeric(data$Low[j])
      close_j <- as.numeric(data$Close[j])

      sl_triggered <- low_j <= stop_loss_price

      cat(sprintf('%-25s %12.8f %12.8f %12.8f %12.8f %10s\n',
                  time_j, open_j, high_j, low_j, close_j,
                  ifelse(sl_triggered, 'OK 是', 'FAIL 否')))

      if (sl_triggered) {
        cat(sprintf('    >>> 止损触发: Low=$%.8f <= SL=$%.8f\n', low_j, stop_loss_price))
        break
      }
    }

    cat('\n')
  }
} else {
  cat('FAIL 未找到05:44:59的K线\n')
}

cat('完成!\n\n')

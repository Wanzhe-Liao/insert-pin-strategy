# 精确定位Close价格=$0.00000684的K线
# 这是R回测的实际入场位置

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

target_price <- 0.00000684
tolerance <- 0.00000001  # 允许1e-8的误差

cat('\n================================================================================\n')
cat('查找Close价格=$0.00000684的K线\n')
cat('================================================================================\n\n')

# 在2025-10-11前后查找
target_date <- as.Date("2025-10-11")
date_indices <- which(as.Date(index(data)) >= target_date - 1 &
                      as.Date(index(data)) <= target_date + 1)

matches <- c()

for (i in date_indices) {
  close_val <- as.numeric(data$Close[i])
  diff_val <- abs(close_val - target_price)

  if (diff_val < tolerance) {
    matches <- c(matches, i)

    cat(sprintf('OK 找���匹配K线:\n'))
    cat(sprintf('  索引: %d\n', i))
    cat(sprintf('  时间: %s\n', as.character(index(data)[i])))
    cat(sprintf('  Open:  $%.8f\n', as.numeric(data$Open[i])))
    cat(sprintf('  High:  $%.8f\n', as.numeric(data$High[i])))
    cat(sprintf('  Low:   $%.8f\n', as.numeric(data$Low[i])))
    cat(sprintf('  Close: $%.8f\n', close_val))
    cat(sprintf('  差异:  $%.10f\n\n', diff_val))
  }
}

if (length(matches) == 0) {
  cat('FAIL 未找到精确匹配的K线\n')
  cat('   尝试扩大搜索范围...\n\n')

  # 找最接近的K线
  all_close <- as.numeric(data$Close[date_indices])
  all_diffs <- abs(all_close - target_price)
  min_idx <- which.min(all_diffs)
  closest_idx <- date_indices[min_idx]

  cat(sprintf('最接近的K线:\n'))
  cat(sprintf('  索引: %d\n', closest_idx))
  cat(sprintf('  时间: %s\n', as.character(index(data)[closest_idx])))
  cat(sprintf('  Close: $%.8f\n', all_close[min_idx]))
  cat(sprintf('  差异:  $%.10f (%.4f%%)\n',
              all_diffs[min_idx],
              all_diffs[min_idx] / target_price * 100))

  matches <- closest_idx
}

# 对每个匹配的K线，检查后续的止损触发情况
cat('\n================================================================================\n')
cat('入场后的止损检查\n')
cat('================================================================================\n\n')

for (match_idx in matches) {
  entry_price <- as.numeric(data$Close[match_idx])
  stop_loss_price <- entry_price * 0.90

  cat(sprintf('入场K线: %s @ $%.8f\n', as.character(index(data)[match_idx]), entry_price))
  cat(sprintf('止损价格: $%.8f\n\n', stop_loss_price))

  cat(sprintf('%-25s %12s %12s %12s %12s %10s\n',
              '时间', 'Open', 'High', 'Low', 'Close', '触发止损?'))
  cat(paste(rep('-', 100), collapse=''), '\n')

  # 检查后续10根K线
  for (i in (match_idx + 1):(match_idx + 10)) {
    if (i > nrow(data)) break

    time_val <- as.character(index(data)[i])
    open_val <- as.numeric(data$Open[i])
    high_val <- as.numeric(data$High[i])
    low_val <- as.numeric(data$Low[i])
    close_val <- as.numeric(data$Close[i])

    sl_triggered <- low_val <= stop_loss_price

    cat(sprintf('%-25s %12.8f %12.8f %12.8f %12.8f %10s\n',
                time_val, open_val, high_val, low_val, close_val,
                ifelse(sl_triggered, 'OK 是', 'FAIL 否')))

    if (sl_triggered) {
      cat(sprintf('  >>> 止损触发! Low=$%.8f <= SL=$%.8f, 使用Close=$%.8f出场\n',
                  low_val, stop_loss_price, close_val))
      cat(sprintf('      盈亏: %.2f%%\n',
                  (close_val - entry_price) / entry_price * 100))
      break
    }
  }

  cat('\n')
}

cat('完成!\n\n')

# 最终信号分析：找出为什么TV和R在不同K线入场
suppressMessages({
  library(xts)
  library(RcppRoll)
})

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

lookbackBars <- 3
minDropPercent <- 20

high_vals <- as.numeric(data[, 'High'])
low_vals <- as.numeric(data[, 'Low'])
close_vals <- as.numeric(data[, 'Close'])

# 计算滚动窗口最高价
window_high <- RcppRoll::roll_max(high_vals, n = lookbackBars, fill = NA, align = "right")
window_high_prev <- c(NA, window_high[1:(length(window_high)-1)])

# 计算跌幅和信号
drop_percent <- (window_high_prev - low_vals) / window_high_prev * 100
signals <- !is.na(drop_percent) & drop_percent >= minDropPercent

cat('=== 交易#4 信号生成详细分析 ===\n\n')

start4 <- as.POSIXct('2024-01-03 18:00:00', tz='UTC')
end4 <- as.POSIXct('2024-01-03 21:00:00', tz='UTC')
subset4 <- data[paste(start4, end4, sep='/')]
idx_start <- which(index(data) == index(subset4)[1])

cat('前置信息:\n')
cat('- lookbackBars = 3 (回看3根K线)\n')
cat('- minDropPercent = 20% (最小跌幅20%)\n')
cat('- window_high_prev = 前3根K线的最高价(滞后1根)\n\n')

for (i in 1:nrow(subset4)) {
  global_idx <- idx_start + i - 1
  time_str <- format(index(subset4)[i], '%Y-%m-%d %H:%M:%S')
  
  marker <- ''
  if (grepl('19:59:59', time_str)) marker <- ' <-- TV入场'
  if (grepl('20:14:59', time_str)) marker <- ' <-- R入场'
  
  cat(sprintf('\nBar %d: %s%s\n', global_idx, time_str, marker))
  cat(sprintf('  OHLC: O=%.8f H=%.8f L=%.8f C=%.8f\n', 
              subset4[i, 'Open'], subset4[i, 'High'], subset4[i, 'Low'], subset4[i, 'Close']))
  cat(sprintf('  Window High (current): %.8f\n', window_high[global_idx]))
  cat(sprintf('  Window High (prev lag): %.8f\n', window_high_prev[global_idx]))
  cat(sprintf('  Drop%%: (%.8f - %.8f) / %.8f * 100 = %.2f%%\n', 
              window_high_prev[global_idx], low_vals[global_idx], 
              window_high_prev[global_idx], drop_percent[global_idx]))
  cat(sprintf('  Signal: %s (需要>= 20%%)\n', ifelse(signals[global_idx], 'YES', 'NO')))
}

cat('\n\n=== 交易#9 信号生成详细分析 ===\n\n')

start9 <- as.POSIXct('2025-10-11 04:30:00', tz='UTC')
end9 <- as.POSIXct('2025-10-11 07:00:00', tz='UTC')
subset9 <- data[paste(start9, end9, sep='/')]
idx_start9 <- which(index(data) == index(subset9)[1])

cat('前置信息: 同上\n\n')

for (i in 1:nrow(subset9)) {
  global_idx <- idx_start9 + i - 1
  time_str <- format(index(subset9)[i], '%Y-%m-%d %H:%M:%S')
  
  marker <- ''
  if (grepl('05:44:59', time_str)) marker <- ' <-- TV入场'
  if (grepl('06:14:59', time_str)) marker <- ' <-- R入场'
  
  cat(sprintf('\nBar %d: %s%s\n', global_idx, time_str, marker))
  cat(sprintf('  OHLC: O=%.8f H=%.8f L=%.8f C=%.8f\n', 
              subset9[i, 'Open'], subset9[i, 'High'], subset9[i, 'Low'], subset9[i, 'Close']))
  cat(sprintf('  Window High (current): %.8f\n', window_high[global_idx]))
  cat(sprintf('  Window High (prev lag): %.8f\n', window_high_prev[global_idx]))
  cat(sprintf('  Drop%%: %.2f%%\n', drop_percent[global_idx]))
  cat(sprintf('  Signal: %s (需要>= 20%%)\n', ifelse(signals[global_idx], 'YES', 'NO')))
}

cat('\n完成\n')

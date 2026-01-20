# 深度分析信号生成差异
suppressMessages({
  library(xts)
  library(RcppRoll)
})

# 加载数据
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

# 参数
lookbackBars <- 3
minDropPercent <- 20

# 手动计算信号（模拟R回测的逻辑）
high_vals <- as.numeric(data[, 'High'])
low_vals <- as.numeric(data[, 'Low'])
close_vals <- as.numeric(data[, 'Close'])
n <- length(high_vals)

# 计算滚动窗口最高价（排除当前K线）
window_high <- RcppRoll::roll_max(high_vals, n = lookbackBars, fill = NA, align = "right")
window_high_prev <- c(NA, window_high[1:(n-1)])  # 滞后1根K线

# 计算跌幅
drop_percent <- (window_high_prev - low_vals) / window_high_prev * 100
signals <- !is.na(drop_percent) & drop_percent >= minDropPercent

cat('=== 交易#4 信号分析 ===\n\n')

# 找到交易#4附近的K线
trade4_tv <- as.POSIXct('2024-01-03 19:59:59', tz='UTC')
trade4_r <- as.POSIXct('2024-01-03 20:14:59', tz='UTC')

idx_tv <- which.min(abs(index(data) - trade4_tv))
idx_r <- which.min(abs(index(data) - trade4_r))

cat(sprintf('TV入场K线: Bar %d, 时间: %s\n', idx_tv, index(data)[idx_tv]))
cat(sprintf('R入场K线:  Bar %d, 时间: %s\n', idx_r, index(data)[idx_r]))
cat('\n')

# 显示前后K线的信号状态
for (i in (idx_tv-2):(idx_r+2)) {
  marker <- ''
  if (i == idx_tv) marker <- ' <-- TV入场'
  if (i == idx_r) marker <- ' <-- R入场'
  
  cat(sprintf('Bar %d (%s):\n', i, index(data)[i]))
  cat(sprintf('  High: %.8f | Low: %.8f | Close: %.8f\n', 
              high_vals[i], low_vals[i], close_vals[i]))
  cat(sprintf('  Window High (prev): %.8f\n', window_high_prev[i]))
  cat(sprintf('  Drop%%: %.2f%% | Signal: %s%s\n\n', 
              drop_percent[i], 
              ifelse(signals[i], 'YES', 'NO'),
              marker))
}

cat('\n=== 交易#9 信号分析 ===\n\n')

# 找到交易#9附近的K线
trade9_tv <- as.POSIXct('2025-10-11 05:44:59', tz='UTC')
trade9_r <- as.POSIXct('2025-10-11 06:14:59', tz='UTC')

idx9_tv <- which.min(abs(index(data) - trade9_tv))
idx9_r <- which.min(abs(index(data) - trade9_r))

cat(sprintf('TV入场K线: Bar %d, 时间: %s\n', idx9_tv, index(data)[idx9_tv]))
cat(sprintf('R入场K线:  Bar %d, 时间: %s\n', idx9_r, index(data)[idx9_r]))
cat('\n')

# 显示前后K线的信号状态
for (i in (idx9_tv-2):(idx9_r+2)) {
  marker <- ''
  if (i == idx9_tv) marker <- ' <-- TV入场'
  if (i == idx9_r) marker <- ' <-- R入场'
  
  cat(sprintf('Bar %d (%s):\n', i, index(data)[i]))
  cat(sprintf('  High: %.8f | Low: %.8f | Close: %.8f\n', 
              high_vals[i], low_vals[i], close_vals[i]))
  cat(sprintf('  Window High (prev): %.8f\n', window_high_prev[i]))
  cat(sprintf('  Drop%%: %.2f%% | Signal: %s%s\n\n', 
              drop_percent[i], 
              ifelse(signals[i], 'YES', 'NO'),
              marker))
}

cat('\n完成\n')

# 分析交易#4和#9的K线数据
suppressMessages(library(xts))

# 加载数据
load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

# 交易#4分析
cat('\n=== 交易#4 K线分析 ===\n')
cat('TV入场: 2024-01-03 19:59:59\n')
cat('R入场:  2024-01-03 20:14:59\n')
cat('差异: +15分钟\n\n')

trade4_start <- as.POSIXct('2024-01-03 19:30:00', tz='UTC')
trade4_end <- as.POSIXct('2024-01-03 20:30:00', tz='UTC')
subset4 <- data[paste(trade4_start, trade4_end, sep='/')]

cat('K线时间范围:\n')
for (i in 1:min(10, nrow(subset4))) {
  cat(sprintf('%d: %s | Close: %.8f\n', i, index(subset4)[i], subset4[i, 'Close']))
}

# 交易#9分析
cat('\n\n=== 交易#9 K线分析 ===\n')
cat('TV入场: 2025-10-11 05:44:59\n')
cat('R入场:  2025-10-11 06:14:59\n')
cat('差异: +30分钟\n\n')

trade9_start <- as.POSIXct('2025-10-11 05:00:00', tz='UTC')
trade9_end <- as.POSIXct('2025-10-11 07:00:00', tz='UTC')
subset9 <- data[paste(trade9_start, trade9_end, sep='/')]

cat('K线时间范围:\n')
for (i in 1:min(10, nrow(subset9))) {
  cat(sprintf('%d: %s | Close: %.8f\n', i, index(subset9)[i], subset9[i, 'Close']))
}

cat('\n完成\n')

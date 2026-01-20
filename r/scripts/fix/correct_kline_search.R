# 正确搜索交易K线
suppressMessages(library(xts))

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('=== 交易#4 正确K线搜索 ===\n\n')

# 从CSV读取准确时间
tv4 <- '2024-01-03 19:59:59'
r4 <- '2024-01-03 20:14:59'

cat('TradingView入场:', tv4, '\n')
cat('R回测入场:', r4, '\n\n')

# 搜索范围
start4 <- as.POSIXct('2024-01-03 19:00:00', tz='UTC')
end4 <- as.POSIXct('2024-01-03 21:00:00', tz='UTC')
subset4 <- data[paste(start4, end4, sep='/')]

cat('该时间段内的K线:\n')
for (i in 1:nrow(subset4)) {
  time_str <- format(index(subset4)[i], '%Y-%m-%d %H:%M:%S')
  marker <- ''
  if (grepl('19:59:59', time_str)) marker <- ' <-- TV入场时间'
  if (grepl('20:14:59', time_str)) marker <- ' <-- R入场时间'
  
  cat(sprintf('%d: %s | Close: %.8f%s\n', i, time_str, subset4[i, 'Close'], marker))
}

cat('\n\n=== 交易#9 正确K线搜索 ===\n\n')

tv9 <- '2025-10-11 05:44:59'
r9 <- '2025-10-11 06:14:59'

cat('TradingView入场:', tv9, '\n')
cat('R回测入场:', r9, '\n\n')

start9 <- as.POSIXct('2025-10-11 05:00:00', tz='UTC')
end9 <- as.POSIXct('2025-10-11 07:00:00', tz='UTC')
subset9 <- data[paste(start9, end9, sep='/')]

cat('该时间段内的K线:\n')
for (i in 1:nrow(subset9)) {
  time_str <- format(index(subset9)[i], '%Y-%m-%d %H:%M:%S')
  marker <- ''
  if (grepl('05:44:59', time_str)) marker <- ' <-- TV入场时间'
  if (grepl('06:14:59', time_str)) marker <- ' <-- R入场时间'
  
  cat(sprintf('%d: %s | Close: %.8f%s\n', i, time_str, subset9[i, 'Close'], marker))
}

cat('\n完成\n')

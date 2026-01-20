# 精确检查2025-10-11那天05:44附近的K线
# 数据存储有8小时偏移，所以05:44实际存储为13:44

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('2025-10-11 那天05:00-07:00范围的K线（数据存储为13:00-15:00）\n')
cat('================================================================================\n\n')

# 搜索2025-10-11整天的数据
target_date <- as.Date('2025-10-11')
date_indices <- which(as.Date(index(data)) == target_date)

# 进一步筛选时间范围：13:00-15:00 (对应UTC 05:00-07:00)
target_indices <- c()
for (i in date_indices) {
  time_str <- format(index(data)[i], '%H:%M')
  hour <- as.numeric(substr(time_str, 1, 2))
  if (hour >= 13 && hour < 15) {
    target_indices <- c(target_indices, i)
  }
}

cat(sprintf('找到 %d 根K线\n\n', length(target_indices)))

cat(sprintf('%-6s %-25s %-25s %12s %12s %12s %12s\n',
            '索引', '存储时间', 'UTC时间', 'Open', 'High', 'Low', 'Close'))
cat(paste(rep('-', 120), collapse=''), '\n')

for (i in target_indices) {
  stored_time <- as.character(index(data)[i])

  # 转换为UTC时间（减8小时）
  utc_time <- index(data)[i] - 8*3600
  utc_str <- as.character(utc_time)

  open_val <- as.numeric(data$Open[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])
  close_val <- as.numeric(data$Close[i])

  marker <- ''
  if (grepl('13:44', stored_time)) marker <- ' ← TV显示的05:44?'
  if (grepl('13:59', stored_time)) marker <- ' ← 有$0.00000684'

  cat(sprintf('%-6d %-25s %-25s %12.8f %12.8f %12.8f %12.8f%s\n',
              i, stored_time, utc_str,
              open_val, high_val, low_val, close_val, marker))
}

cat('\n')

# 具体分析13:44和13:59两根K线
cat('================================================================================\n')
cat('关键K线对比\n')
cat('================================================================================\n\n')

# 13:44 K线 (UTC 05:44)
idx_1344 <- which(grepl('2025-10-11 13:44', as.character(index(data))))
if (length(idx_1344) > 0) {
  idx_1344 <- idx_1344[1]
  cat('K线 #1: 存储时间 13:44 (UTC 05:44)\n')
  cat(sprintf('  索引: %d\n', idx_1344))
  cat(sprintf('  Close: $%.8f\n', as.numeric(data$Close[idx_1344])))
  cat('\n')
}

# 13:59 K线 (UTC 05:59)
idx_1359 <- which(grepl('2025-10-11 13:59', as.character(index(data))))
if (length(idx_1359) > 0) {
  idx_1359 <- idx_1359[1]
  cat('K线 #2: 存储时间 13:59 (UTC 05:59)\n')
  cat(sprintf('  索引: %d\n', idx_1359))
  cat(sprintf('  Close: $%.8f\n', as.numeric(data$Close[idx_1359])))

  if (abs(as.numeric(data$Close[idx_1359]) - 0.00000684) < 1e-10) {
    cat('  OK 这根K线的Close价格=$0.00000684（精确匹配）\n')
  }
  cat('\n')
}

# 对比
if (length(idx_1344) > 0 && length(idx_1359) > 0) {
  close_1344 <- as.numeric(data$Close[idx_1344])
  close_1359 <- as.numeric(data$Close[idx_1359])

  cat('结论:\n')
  cat(sprintf('  TradingView显示入场时间: 05:44:59\n'))
  cat(sprintf('  TradingView显示入场价格: $0.00000684\n'))
  cat(sprintf('  13:44 (UTC 05:44) Close价格: $%.8f %s\n',
              close_1344,
              ifelse(abs(close_1344 - 0.00000684) < 1e-8, 'OK 匹配', 'FAIL 不匹配')))
  cat(sprintf('  13:59 (UTC 05:59) Close价格: $%.8f %s\n',
              close_1359,
              ifelse(abs(close_1359 - 0.00000684) < 1e-8, 'OK 匹配', 'FAIL 不匹配')))
  cat('\n')

  if (abs(close_1359 - 0.00000684) < 1e-8) {
    cat('💡 推断: TradingView可能是在05:44检测到信号，但在05:59执行入场\n')
    cat('        这符合Pine Script的process_orders_on_close=true行为\n')
    cat('        （信号检测后，在下一根K线的收盘价执行）\n')
  }
}

cat('\n完成!\n\n')

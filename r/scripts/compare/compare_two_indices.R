# 对比索引85360和85392，查看它们的真实时间戳

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('对比两个索引的K线数据\n')
cat('================================================================================\n\n')

# 检查索引85360
cat('索引 85360:\n')
cat(sprintf('  时间: %s\n', as.character(index(data)[85360])))
cat(sprintf('  时间类: %s\n', class(index(data)[85360])))
cat(sprintf('  时区: %s\n', attr(index(data)[85360], 'tzone')))
cat(sprintf('  Open:  $%.8f\n', as.numeric(data$Open[85360])))
cat(sprintf('  High:  $%.8f\n', as.numeric(data$High[85360])))
cat(sprintf('  Low:   $%.8f\n', as.numeric(data$Low[85360])))
cat(sprintf('  Close: $%.8f\n', as.numeric(data$Close[85360])))
cat('\n')

# 检查索引85392
cat('索引 85392:\n')
cat(sprintf('  时间: %s\n', as.character(index(data)[85392])))
cat(sprintf('  时间类: %s\n', class(index(data)[85392])))
cat(sprintf('  时区: %s\n', attr(index(data)[85392], 'tzone')))
cat(sprintf('  Open:  $%.8f\n', as.numeric(data$Open[85392])))
cat(sprintf('  High:  $%.8f\n', as.numeric(data$High[85392])))
cat(sprintf('  Low:   $%.8f\n', as.numeric(data$Low[85392])))
cat(sprintf('  Close: $%.8f\n', as.numeric(data$Close[85392])))
cat('\n')

# 计算时间差
time_diff <- as.numeric(difftime(index(data)[85392], index(data)[85360], units='hours'))
cat(sprintf('时间差: %.1f 小时 (%.0f根K线)\n', time_diff, time_diff * 4))
cat('\n')

# 查找所有Close=$0.00000684的索引
cat('================================================================================\n')
cat('查找所有Close=$0.00000684的K线索引\n')
cat('================================================================================\n\n')

close_vec <- as.numeric(data$Close)
matches <- which(abs(close_vec - 0.00000684) < 1e-10)

cat(sprintf('找到 %d 个匹配:\n\n', length(matches)))

for (idx in matches[1:min(10, length(matches))]) {
  cat(sprintf('索引 %d: %s, Close=$%.8f\n',
              idx, as.character(index(data)[idx]), as.numeric(data$Close[idx])))
}

# 特别检查包含2025-10-11 05:的所有索引
cat('\n')
cat('================================================================================\n')
cat('2025-10-11 05:00-06:00范围内的所有K线\n')
cat('================================================================================\n\n')

# 使用字符串匹配避免时区问题
time_strings <- as.character(index(data))
matches_0511_05 <- grep('2025-10-11 05:', time_strings)

cat(sprintf('%-6s %-30s %12s %12s %12s %12s\n',
            '索引', '时间', 'Open', 'High', 'Low', 'Close'))
cat(paste(rep('-', 100), collapse=''), '\n')

for (idx in matches_0511_05) {
  cat(sprintf('%-6d %-30s %12.8f %12.8f %12.8f %12.8f%s\n',
              idx,
              as.character(index(data)[idx]),
              as.numeric(data$Open[idx]),
              as.numeric(data$High[idx]),
              as.numeric(data$Low[idx]),
              as.numeric(data$Close[idx]),
              ifelse(abs(as.numeric(data$Close[idx]) - 0.00000684) < 1e-10,
                     ' ← Close=$0.00000684', '')))
}

cat('\n完成!\n\n')

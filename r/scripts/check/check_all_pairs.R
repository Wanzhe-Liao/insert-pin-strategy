# 检查RData中所有交易对

library(xts)
load('data/liaochu.RData')

cat('\n================================================================================\n')
cat('RData文件中的所有交易对\n')
cat('================================================================================\n\n')

all_pairs <- names(cryptodata)
cat(sprintf('共 %d 个交易对:\n\n', length(all_pairs)))

for (pair in all_pairs) {
  data <- cryptodata[[pair]]
  cat(sprintf('%-20s: %6d根K线, %s 至 %s\n',
              pair,
              nrow(data),
              as.character(index(data)[1]),
              as.character(index(data)[nrow(data)])))
}

cat('\n')
cat('================================================================================\n')
cat('PEPEUSDT相关交易对详细信息\n')
cat('================================================================================\n\n')

pepe_pairs <- all_pairs[grepl('PEPE', all_pairs)]

if (length(pepe_pairs) > 0) {
  for (pair in pepe_pairs) {
    data <- cryptodata[[pair]]
    cat(sprintf('%s:\n', pair))
    cat(sprintf('  数据行数: %d\n', nrow(data)))
    cat(sprintf('  起始时间: %s\n', as.character(index(data)[1])))
    cat(sprintf('  结束时间: %s\n', as.character(index(data)[nrow(data)])))
    cat(sprintf('  第一个收盘价: $%.8f\n', as.numeric(data$Close[1])))
    cat(sprintf('  最后一个收盘价: $%.8f\n', as.numeric(data$Close[nrow(data)])))

    # 检查2025-10-11 05:59的价格
    target_time <- as.POSIXct('2025-10-11 05:59:59', tz='UTC')
    time_idx <- which(abs(as.numeric(difftime(index(data), target_time, units='secs'))) < 2)

    if (length(time_idx) > 0) {
      cat(sprintf('  2025-10-11 05:59:59收盘价: $%.8f\n', as.numeric(data$Close[time_idx[1]])))
    }
    cat('\n')
  }
} else {
  cat('WARN 没有找到PEPEUSDT交易对!\n\n')
}

cat('完成!\n')

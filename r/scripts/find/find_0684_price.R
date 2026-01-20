# 查找价格$0.00000684出现在哪根K线

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

target_price <- 0.00000684

# 查找2025-10-11前后的K线
target_date <- as.Date("2025-10-11")
day_indices <- which(as.Date(index(data)) >= target_date - 1 & as.Date(index(data)) <= target_date + 1)

cat('\n查找价格$0.00000684:\n')
cat(paste(rep('=', 100), collapse=''), '\n\n')

best_match_idx <- NA
best_match_diff <- Inf
best_match_type <- ""

for (i in day_indices) {
  open_val <- as.numeric(data$Open[i])
  close_val <- as.numeric(data$Close[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])

  # 检查各个价格
  open_diff <- abs(open_val - target_price)
  close_diff <- abs(close_val - target_price)
  high_diff <- abs(high_val - target_price)
  low_diff <- abs(low_val - target_price)

  min_diff <- min(open_diff, close_diff, high_diff, low_diff)

  if (min_diff < best_match_diff) {
    best_match_diff <- min_diff
    best_match_idx <- i

    if (min_diff == open_diff) best_match_type <- "Open"
    else if (min_diff == close_diff) best_match_type <- "Close"
    else if (min_diff == high_diff) best_match_type <- "High"
    else best_match_type <- "Low"
  }

  # 如果差异小于0.5%，打印出来
  if ((min_diff / target_price * 100) < 0.5) {
    cat(sprintf('时间: %s\n', as.character(index(data)[i])))
    cat(sprintf('  Open:  $%.8f (差异 %.4f%%)\n', open_val, open_diff/target_price*100))
    cat(sprintf('  High:  $%.8f (差异 %.4f%%)\n', high_val, high_diff/target_price*100))
    cat(sprintf('  Low:   $%.8f (差异 %.4f%%)\n', low_val, low_diff/target_price*100))
    cat(sprintf('  Close: $%.8f (差异 %.4f%%)\n', close_val, close_diff/target_price*100))
    cat('\n')
  }
}

cat(paste(rep('=', 100), collapse=''), '\n')
cat('最接近的K线:\n')
cat(paste(rep('=', 100), collapse=''), '\n\n')

if (!is.na(best_match_idx)) {
  cat(sprintf('时间: %s\n', as.character(index(data)[best_match_idx])))
  cat(sprintf('匹配价格类型: %s\n', best_match_type))
  cat(sprintf('Open:  $%.8f\n', as.numeric(data$Open[best_match_idx])))
  cat(sprintf('High:  $%.8f\n', as.numeric(data$High[best_match_idx])))
  cat(sprintf('Low:   $%.8f\n', as.numeric(data$Low[best_match_idx])))
  cat(sprintf('Close: $%.8f\n', as.numeric(data$Close[best_match_idx])))
  cat(sprintf('差异: $%.10f (%.4f%%)\n', best_match_diff, best_match_diff/target_price*100))
}

cat('\n完成!\n')

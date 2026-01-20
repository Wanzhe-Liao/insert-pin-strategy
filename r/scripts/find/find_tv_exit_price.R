# 查找TradingView的出场价格$0.00000753在哪根K线

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

target_exit_price <- 0.00000753
target_exit_date <- as.Date('2025-10-13')

cat('\n================================================================================\n')
cat('查找TradingView交易#9的出场价格$0.00000753\n')
cat('================================================================================\n\n')

# 搜索2025-10-13的所有K线
date_indices <- which(as.Date(index(data)) == target_exit_date)

cat(sprintf('2025-10-13共有 %d 根K线\n\n', length(date_indices)))

# 查找最接近的价格
best_match_idx <- NA
best_match_diff <- Inf
best_match_type <- ""

for (i in date_indices) {
  open_val <- as.numeric(data$Open[i])
  close_val <- as.numeric(data$Close[i])
  high_val <- as.numeric(data$High[i])
  low_val <- as.numeric(data$Low[i])

  open_diff <- abs(open_val - target_exit_price)
  close_diff <- abs(close_val - target_exit_price)
  high_diff <- abs(high_val - target_exit_price)
  low_diff <- abs(low_val - target_exit_price)

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
  if ((min_diff / target_exit_price * 100) < 0.5) {
    cat(sprintf('时间: %s\n', as.character(index(data)[i])))
    cat(sprintf('  Open:  $%.8f (差异 %.4f%%)%s\n',
                open_val, open_diff/target_exit_price*100,
                ifelse(min_diff == open_diff, ' ← 最接近', '')))
    cat(sprintf('  High:  $%.8f (差异 %.4f%%)%s\n',
                high_val, high_diff/target_exit_price*100,
                ifelse(min_diff == high_diff, ' ← 最接近', '')))
    cat(sprintf('  Low:   $%.8f (差异 %.4f%%)%s\n',
                low_val, low_diff/target_exit_price*100,
                ifelse(min_diff == low_diff, ' ← 最接近', '')))
    cat(sprintf('  Close: $%.8f (差异 %.4f%%)%s\n',
                close_val, close_diff/target_exit_price*100,
                ifelse(min_diff == close_diff, ' ← 最接近', '')))
    cat('\n')
  }
}

cat('================================================================================\n')
cat('最接近的K线\n')
cat('================================================================================\n\n')

if (!is.na(best_match_idx)) {
  cat(sprintf('索引: %d\n', best_match_idx))
  cat(sprintf('时间: %s\n', as.character(index(data)[best_match_idx])))
  cat(sprintf('匹配类型: %s\n', best_match_type))
  cat(sprintf('Open:  $%.8f\n', as.numeric(data$Open[best_match_idx])))
  cat(sprintf('High:  $%.8f\n', as.numeric(data$High[best_match_idx])))
  cat(sprintf('Low:   $%.8f\n', as.numeric(data$Low[best_match_idx])))
  cat(sprintf('Close: $%.8f\n', as.numeric(data$Close[best_match_idx])))
  cat(sprintf('差异:  $%.10f (%.4f%%)\n\n', best_match_diff,
              best_match_diff/target_exit_price*100))

  # 如果是High触发，说明是止盈
  if (best_match_type == "High" || best_match_type == "Close") {
    cat('💡 推断: 这是止盈出场\n')

    # 验证从不同入场点到此处的盈亏
    entry_price <- 0.00000684
    exit_price <- as.numeric(data[[best_match_type]][best_match_idx])
    pnl <- (exit_price - entry_price) / entry_price * 100

    cat(sprintf('\n从入场价$%.8f到出场价$%.8f:\n', entry_price, exit_price))
    cat(sprintf('  盈亏: %.2f%%\n', pnl))

    if (abs(pnl - 9.92) < 0.5) {
      cat('  OK 与TradingView的9.92%盈亏匹配!\n')
    }
  }
}

cat('\n完成!\n\n')

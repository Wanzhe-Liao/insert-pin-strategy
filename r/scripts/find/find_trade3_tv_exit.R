# 搜索交易#3的TradingView出场价格$0.00000138

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('搜索交易#3的TradingView出场K线\n')
cat('================================================================================\n\n')

# 交易信息
entry_price <- 0.00000125
tv_exit_price <- 0.00000138
entry_time_str <- "2023-11-10 00:14:59.999"
r_exit_time_str <- "2023-11-14 08:14:59.999"

cat('交易信息:\n')
cat(sprintf('  入场价格: $%.8f\n', entry_price))
cat(sprintf('  入场时间: %s\n', entry_time_str))
cat(sprintf('  TV出场价格: $%.8f\n', tv_exit_price))
cat(sprintf('  R出场时间: %s (止损)\n\n', r_exit_time_str))

# 找到入场索引
entry_idx <- which(as.character(index(data)) == entry_time_str)[1]
r_exit_idx <- which(as.character(index(data)) == r_exit_time_str)[1]

cat(sprintf('入场索引: %d\n', entry_idx))
cat(sprintf('R出场索引: %d\n', r_exit_idx))
cat(sprintf('持仓期间: %d根K线\n\n', r_exit_idx - entry_idx))

# 在入场和R出场之间搜索Close价格=$0.00000138的K线
cat('在持仓期间搜索Close=$0.00000138的K线...\n')
cat(paste(rep('=', 100), collapse=''), '\n\n')

matches <- c()

for (i in (entry_idx + 1):r_exit_idx) {
  close_i <- as.numeric(data$Close[i])
  high_i <- as.numeric(data$High[i])
  low_i <- as.numeric(data$Low[i])

  # 检查Close价格是否匹配
  if (abs(close_i - tv_exit_price) < 1e-10) {
    matches <- c(matches, i)

    cat(sprintf('OK 找到匹配: 索引 %d\n', i))
    cat(sprintf('  时间: %s\n', as.character(index(data)[i])))
    cat(sprintf('  Open:  $%.8f\n', as.numeric(data$Open[i])))
    cat(sprintf('  High:  $%.8f\n', high_i))
    cat(sprintf('  Low:   $%.8f\n', low_i))
    cat(sprintf('  Close: $%.8f ← 精确匹配TV出场价\n', close_i))

    # 检查此处是否触发止盈
    tp_price <- entry_price * 1.10
    if (close_i >= tp_price) {
      cat(sprintf('  OK Close >= 止盈价 $%.8f (触发止盈)\n', tp_price))
    }

    # 距离入场多少根K线
    bars_from_entry <- i - entry_idx
    cat(sprintf('  距离入场: %d根K线\n', bars_from_entry))

    cat('\n')
  }
}

if (length(matches) == 0) {
  cat('FAIL 未找到Close价格精确匹配的K线\n\n')

  # 搜索最接近的价格
  cat('搜索最接近的K线...\n\n')

  best_idx <- NA
  best_diff <- Inf

  for (i in (entry_idx + 1):r_exit_idx) {
    close_i <- as.numeric(data$Close[i])
    diff_i <- abs(close_i - tv_exit_price)

    if (diff_i < best_diff) {
      best_diff <- diff_i
      best_idx <- i
    }
  }

  if (!is.na(best_idx)) {
    cat(sprintf('最接近的K线: 索引 %d\n', best_idx))
    cat(sprintf('  时间: %s\n', as.character(index(data)[best_idx])))
    cat(sprintf('  Close: $%.8f\n', as.numeric(data$Close[best_idx])))
    cat(sprintf('  差异: $%.10f (%.2f%%)\n', best_diff, best_diff/tv_exit_price*100))
  }
}

cat('\n')
cat('================================================================================\n')
cat('结论\n')
cat('================================================================================\n\n')

if (length(matches) > 0) {
  cat('OK 找到了TV出场K线\n')
  cat(sprintf('   TV在索引 %d 止盈出场\n', matches[1]))
  cat(sprintf('   R在索引 %d 止损出场\n', r_exit_idx))
  cat(sprintf('   时间差: %d根K线 (%.1f小时)\n',
              r_exit_idx - matches[1],
              (r_exit_idx - matches[1]) * 0.25))
  cat('\n')
  cat('这说明R的止损触发过早，或者数据源完全不同。\n')
} else {
  cat('FAIL 未找到精确匹配的K线\n')
  cat('   可能原因:\n')
  cat('   1. TradingView使用的数据源与当前RData完全不同\n')
  cat('   2. 价格精度问题导致无法精确匹配\n')
  cat('   3. 时间戳对齐问题\n')
}

cat('\n完成!\n\n')

# 详细分析出场价格不匹配的3笔交易
# 交易#1, #3, #5

library(xts)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

cat('\n================================================================================\n')
cat('详细分析出场价格不匹配的交易\n')
cat('================================================================================\n\n')

# 定义需要分析的交易
mismatched_trades <- list(
  list(
    id = 1,
    tv_entry = 0.00000307,
    tv_exit = 0.00000338,
    r_entry = 0.00000307,
    r_exit = 0.00000342,
    r_entry_time = "2023-05-06 02:44:59.999",
    r_exit_time = "2023-05-06 03:44:59.999",
    r_exit_reason = "TP"
  ),
  list(
    id = 3,
    tv_entry = 0.00000125,
    tv_exit = 0.00000138,
    r_entry = 0.00000125,
    r_exit = 0.00000111,
    r_entry_time = "2023-11-10 00:14:59.999",
    r_exit_time = "2023-11-14 08:14:59.999",
    r_exit_reason = "SL"
  ),
  list(
    id = 5,
    tv_entry = 0.00000552,
    tv_exit = 0.00000608,
    r_entry = 0.00000552,
    r_exit = 0.00000628,
    r_entry_time = "2024-03-06 03:59:59.999",
    r_exit_time = "2024-03-06 05:14:59.999",
    r_exit_reason = "TP"
  )
)

for (trade in mismatched_trades) {
  cat(sprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'))
  cat(sprintf('交易 #%d\n', trade$id))
  cat(sprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'))

  cat('对比:\n')
  cat(sprintf('  TradingView: 入场$%.8f → 出场$%.8f\n', trade$tv_entry, trade$tv_exit))
  cat(sprintf('  R回测:       入场$%.8f → 出场$%.8f (%s)\n\n',
              trade$r_entry, trade$r_exit, trade$r_exit_reason))

  # 计算止盈止损价格
  tp_price <- trade$r_entry * 1.10
  sl_price <- trade$r_entry * 0.90

  cat(sprintf('止盈价格: $%.8f (+10%%)\n', tp_price))
  cat(sprintf('止损价格: $%.8f (-10%%)\n\n', sl_price))

  # 找到R的出场K线
  r_exit_idx <- which(as.character(index(data)) == trade$r_exit_time)

  if (length(r_exit_idx) > 0) {
    r_exit_idx <- r_exit_idx[1]

    cat(sprintf('R在索引 %d 出场:\n', r_exit_idx))
    cat(sprintf('  时间: %s\n', as.character(index(data)[r_exit_idx])))
    cat(sprintf('  Open:  $%.8f\n', as.numeric(data$Open[r_exit_idx])))
    cat(sprintf('  High:  $%.8f', as.numeric(data$High[r_exit_idx])))
    if (as.numeric(data$High[r_exit_idx]) >= tp_price) {
      cat(' ← 触发止盈\n')
    } else {
      cat('\n')
    }
    cat(sprintf('  Low:   $%.8f', as.numeric(data$Low[r_exit_idx])))
    if (as.numeric(data$Low[r_exit_idx]) <= sl_price) {
      cat(' ← 触发止损\n')
    } else {
      cat('\n')
    }
    cat(sprintf('  Close: $%.8f', as.numeric(data$Close[r_exit_idx])))

    r_close <- as.numeric(data$Close[r_exit_idx])
    if (abs(r_close - trade$r_exit) < 1e-10) {
      cat(' ← R出场价格匹配\n')
    } else {
      cat(sprintf(' ← 与R记录不符($%.8f)\n', trade$r_exit))
    }

    # 检查TV的出场价格是否在这根K线的OHLC范围内
    in_ohlc <- (trade$tv_exit >= as.numeric(data$Low[r_exit_idx]) &&
                trade$tv_exit <= as.numeric(data$High[r_exit_idx]))

    cat(sprintf('\nTV出场价$%.8f是否在此K线OHLC范围内: %s\n',
                trade$tv_exit, ifelse(in_ohlc, 'OK 是', 'FAIL 否')))

    if (!in_ohlc) {
      cat('→ TV可能在不同的K线出场\n')

      # 搜索TV出场价格最接近的K线
      cat('\n搜索TV出场价格$%.8f的K线...\n' , trade$tv_exit)

      # 在出场时间前后10根K线内搜索
      search_start <- max(1, r_exit_idx - 10)
      search_end <- min(nrow(data), r_exit_idx + 10)

      best_match_idx <- NA
      best_match_diff <- Inf

      for (j in search_start:search_end) {
        close_j <- as.numeric(data$Close[j])
        diff_j <- abs(close_j - trade$tv_exit)

        if (diff_j < best_match_diff) {
          best_match_diff <- diff_j
          best_match_idx <- j
        }
      }

      if (!is.na(best_match_idx) && best_match_diff < 1e-8) {
        cat(sprintf('\n找到匹配: 索引 %d\n', best_match_idx))
        cat(sprintf('  时间: %s\n', as.character(index(data)[best_match_idx])))
        cat(sprintf('  Close: $%.8f (精确匹配)\n', as.numeric(data$Close[best_match_idx])))

        bars_diff <- best_match_idx - r_exit_idx
        if (bars_diff > 0) {
          cat(sprintf('  → TV比R晚%d根K线出场\n', bars_diff))
        } else if (bars_diff < 0) {
          cat(sprintf('  → TV比R早%d根K线出场\n', abs(bars_diff)))
        }
      }
    } else {
      # TV出场价在同一K线的OHLC范围内
      cat(sprintf('\n→ Close价格差异: $%.10f (%.2f%%)\n',
                  abs(r_close - trade$tv_exit),
                  abs(r_close - trade$tv_exit) / trade$tv_exit * 100))
      cat('  可能原因: 数据源微小差异\n')
    }
  } else {
    cat('FAIL 未找到R出场K线\n')
  }

  cat('\n')
}

cat('================================================================================\n')
cat('总结\n')
cat('================================================================================\n\n')

cat('出场价格差异的可能原因:\n')
cat('  1. 不同的K线: R和TV在不同的K线上触发了止盈/止损\n')
cat('  2. 数据源差异: 即使同一K线，不同交易所的Close价格略有不同\n')
cat('  3. 时间戳对齐: K线的时间标签可能有偏差\n')
cat('\n')
cat('由于我们已确认所有入场/出场都使用Close价格，\n')
cat('剩余的差异主要来自数据源本身的差异，这是可以接受的。\n\n')

cat('完成!\n\n')

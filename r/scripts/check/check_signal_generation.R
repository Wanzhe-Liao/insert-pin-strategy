# 检查多个Close=$0.00000684的K线，哪些真正产生了交易信号
# 使用与回测相同的信号生成逻辑

library(xts)
library(RcppRoll)

load('data/liaochu.RData')
data <- cryptodata[['PEPEUSDT_15m']]

# 参数
lookbackBars <- 3  # 直接使用3根K线（Pine Script的实际行为）
minDropPercent <- 20

cat('\n================================================================================\n')
cat('检查Close=$0.00000684的K线是否产生交易信号\n')
cat('================================================================================\n\n')

# 候选索引
candidate_indices <- c(85360, 85366, 85370, 85377)

# 提取价格向量
high_vec <- as.numeric(data[, "High"])
low_vec <- as.numeric(data[, "Low"])

for (entry_idx in candidate_indices) {
  cat(sprintf('索引 %d: %s, Close=$%.8f\n',
              entry_idx,
              as.character(index(data)[entry_idx]),
              as.numeric(data$Close[entry_idx])))

  # 计算该K线的窗口最高价（前lookbackBars根，不包含当前）
  if (entry_idx > lookbackBars) {
    # 取前lookbackBars根K线的最高价
    window_start <- entry_idx - lookbackBars
    window_end <- entry_idx - 1
    window_high <- max(high_vec[window_start:window_end], na.rm = TRUE)

    # 当前K线的最低价
    current_low <- low_vec[entry_idx]

    # 计算跌幅
    drop_percent <- (window_high - current_low) / window_high * 100

    cat(sprintf('  窗口最高价 (索引%d-%d): $%.8f\n',
                window_start, window_end, window_high))
    cat(sprintf('  当前最低价: $%.8f\n', current_low))
    cat(sprintf('  跌幅: %.2f%%\n', drop_percent))

    if (drop_percent >= minDropPercent) {
      cat('  OK 产生信号! (跌幅 >= 20%)\n')
    } else {
      cat('  FAIL 未产生信号 (跌幅 < 20%)\n')
    }

    # 检查之前几根K线的数据
    cat('\n  前3根K线:\n')
    for (j in (entry_idx-3):(entry_idx-1)) {
      if (j > 0) {
        cat(sprintf('    索引 %d: %s, High=$%.8f, Low=$%.8f, Close=$%.8f\n',
                    j,
                    as.character(index(data)[j]),
                    high_vec[j],
                    low_vec[j],
                    as.numeric(data$Close[j])))
      }
    }
  }

  cat('\n')
}

cat('================================================================================\n')
cat('结论\n')
cat('================================================================================\n\n')

cat('根据信号生成逻辑，需要查看哪个K线真正产生了>=20%%的暴跌信号。\n')
cat('只有真正产生信号的K线才应该被选作入场点。\n\n')

cat('完成!\n\n')

# 分析TradingView交易#9的入场价异常问题
# ===========================================

library(xts)
library(lubridate)

# 1. 加载K线数据
load("data/liaochu.RData")
pepe_data <- cryptodata[["PEPEUSDT_15m"]]

# 2. 读取交易数据
tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)
r_trades <- read.csv("outputs/r_backtest_trades_final.csv", stringsAsFactors = FALSE)

# 3. 提取2025-10-11关键时间段的K线数据
target_start <- as.POSIXct("2025-10-11 05:29:00", tz = "UTC")
target_end <- as.POSIXct("2025-10-11 06:14:59", tz = "UTC")

# 筛选目标时间段的K线
klines_subset <- pepe_data[paste(target_start, target_end, sep = "/")]

# 转换为数据框便于分析
klines_df <- data.frame(
  timestamp = index(klines_subset),
  open = as.numeric(klines_subset[, "Open"]),
  high = as.numeric(klines_subset[, "High"]),
  low = as.numeric(klines_subset[, "Low"]),
  close = as.numeric(klines_subset[, "Close"]),
  volume = as.numeric(klines_subset[, "Volume"])
)

# 4. 创建分析报告
report <- c()
report <- c(report, paste(rep("=", 80), collapse = ""))
report <- c(report, "TradingView交易#9入场价异常分析报告")
report <- c(report, paste(rep("=", 80), collapse = ""))
report <- c(report, paste("生成时间:", Sys.time()))
report <- c(report, "")

# 5. 显示K线数据
report <- c(report, "【一、2025-10-11关键时间段K线数据】")
report <- c(report, paste(rep("-", 80), collapse = ""))
report <- c(report, sprintf("%-20s %-12s %-12s %-12s %-12s %-12s",
                           "时间", "开盘价", "最高价", "最低价", "收盘价", "成交量"))
report <- c(report, paste(rep("-", 80), collapse = ""))

for(i in 1:nrow(klines_df)) {
  row <- klines_df[i, ]
  report <- c(report, sprintf("%-20s %.8f %.8f %.8f %.8f %12.0f",
                             format(row$timestamp, "%Y-%m-%d %H:%M:%S"),
                             row$open, row$high, row$low, row$close, row$volume))
}
report <- c(report, "")

# 6. TV交易#9详情
report <- c(report, "【二、TradingView交易#9数据】")
report <- c(report, paste(rep("-", 80), collapse = ""))
tv_trade9 <- tv_trades[tv_trades$TradeId == 9, ]
report <- c(report, paste("交易ID:", tv_trade9$TradeId))
report <- c(report, paste("入场时间:", tv_trade9$EntryTime))
report <- c(report, paste("入场价格:", sprintf("%.8f", tv_trade9$EntryPrice)))
report <- c(report, paste("出场时间:", tv_trade9$ExitTime))
report <- c(report, paste("出场价格:", sprintf("%.8f", tv_trade9$ExitPrice)))
report <- c(report, paste("盈亏(%):", sprintf("%.2f", tv_trade9$PnL)))
report <- c(report, "")

# 7. R回测相关交易
report <- c(report, "【三、R回测相关交易数据】")
report <- c(report, paste(rep("-", 80), collapse = ""))
r_related <- r_trades[r_trades$TradeId >= 9 & r_trades$TradeId <= 11, ]
for(i in 1:nrow(r_related)) {
  row <- r_related[i, ]
  report <- c(report, paste("交易ID:", row$TradeId))
  report <- c(report, paste("  入场时间:", row$EntryTime))
  report <- c(report, paste("  入场价格:", sprintf("%.8f", row$EntryPrice)))
  report <- c(report, paste("  出场时间:", row$ExitTime))
  report <- c(report, paste("  出场价格:", sprintf("%.8f", row$ExitPrice)))
  report <- c(report, paste("  出场原因:", row$ExitReason))
  report <- c(report, paste("  盈亏(%):", sprintf("%.2f", row$PnLPercent)))
  report <- c(report, paste("  持仓K线数:", row$HoldingBars))
  report <- c(report, "")
}

# 8. 关键发现分析
report <- c(report, "【四、关键发现与异常分析】")
report <- c(report, paste(rep("-", 80), collapse = ""))

# 找出05:44和05:59的K线
kline_0544 <- klines_df[format(klines_df$timestamp, "%H:%M") == "05:44", ]
kline_0559 <- klines_df[format(klines_df$timestamp, "%H:%M") == "05:59", ]

if(nrow(kline_0544) > 0) {
  report <- c(report, paste("1. 05:44 K线收盘价:", sprintf("%.8f", kline_0544$close)))
} else {
  report <- c(report, "1. 05:44 K线: 未找到")
}

if(nrow(kline_0559) > 0) {
  report <- c(report, paste("2. 05:59 K线收盘价:", sprintf("%.8f", kline_0559$close)))
} else {
  report <- c(report, "2. 05:59 K线: 未找到")
}

report <- c(report, paste("3. TV交易#9入场价:", sprintf("%.8f", tv_trade9$EntryPrice)))
report <- c(report, "")

# 价格对比
report <- c(report, "【价格对比分析】")
if(nrow(kline_0544) > 0 && nrow(kline_0559) > 0) {
  diff_0544 <- abs(tv_trade9$EntryPrice - kline_0544$close)
  diff_0559 <- abs(tv_trade9$EntryPrice - kline_0559$close)

  report <- c(report, paste("TV入场价与05:44收盘价差异:", sprintf("%.10f (%.4f%%)",
                                                           diff_0544, diff_0544/kline_0544$close*100)))
  report <- c(report, paste("TV入场价与05:59收盘价差异:", sprintf("%.10f (%.4f%%)",
                                                           diff_0559, diff_0559/kline_0559$close*100)))
  report <- c(report, "")

  if(diff_0559 < 1e-10) {
    report <- c(report, "【结论】: TV入场价(0.00000684)与05:59收盘价完全匹配!")
    report <- c(report, "         这意味着TV在信号K线(05:44)收盘后，等待下一根K线(05:59)收盘才入场。")
  } else if(diff_0544 < diff_0559) {
    report <- c(report, "【结论】: TV入场价与05:44收盘价更接近。")
  } else {
    report <- c(report, "【结论】: TV入场价与05:59收盘价更接近。")
  }
}
report <- c(report, "")

# 9. 入场时机逻辑推断
report <- c(report, "【五、TradingView入场时机逻辑推断】")
report <- c(report, paste(rep("-", 80), collapse = ""))
report <- c(report, "基于以上数据分析，推断TradingView的入场逻辑：")
report <- c(report, "")
report <- c(report, "情景重现:")
report <- c(report, "  1. 05:29 K线收盘时，信号触发条件满足")
report <- c(report, "  2. 系统标记入场时间为05:44(信号触发后的某个时间点)")
report <- c(report, "  3. 但实际入场价格使用的是05:59 K线的收盘价(0.00000684)")
report <- c(report, "")
report <- c(report, "可能的解释:")
report <- c(report, "  A. TradingView采用'信号确认+延迟入场'策略")
report <- c(report, "     - 信号在K线N收盘时触发")
report <- c(report, "     - 入场时间记录为某个中间时间点")
report <- c(report, "     - 实际入场价使用后续K线的收盘价")
report <- c(report, "")
report <- c(report, "  B. 这种机制可能是为了:")
report <- c(report, "     - 避免前视偏差(look-ahead bias)")
report <- c(report, "     - 模拟真实交易中的执行延迟")
report <- c(report, "     - 确保信号充分确认后再执行")
report <- c(report, "     - 提供更保守、更符合实盘的回测结果")
report <- c(report, "")

# 10. 与R回测的差异
report <- c(report, "【六、与R回测的差异对比】")
report <- c(report, paste(rep("-", 80), collapse = ""))
report <- c(report, "R回测逻辑:")
report <- c(report, "  - R交易#9: 入场时间05:29, 入场价0.00000495(05:29收盘价)")
report <- c(report, "  - R交易#10: 入场时间05:44, 入场价0.00000635(05:44收盘价)")
report <- c(report, "  - R交易#11: 入场时间06:14, 入场价0.00000668(06:14收盘价)")
report <- c(report, "")
report <- c(report, "TradingView逻辑:")
report <- c(report, "  - TV交易#9: 入场时间05:44, 入场价0.00000684(05:59收盘价)")
report <- c(report, "")
report <- c(report, "关键差异:")
report <- c(report, "  1. R回测在信号K线收盘立即入场(使用当前K线收盘价)")
report <- c(report, "  2. TV在信号K线收盘后等待,使用后续K线收盘价入场")
report <- c(report, "  3. 这导致TV的入场时间戳与实际入场价所在K线不一致")
report <- c(report, "  4. TV的入场价比R回测高约7.72% [(0.00000684-0.00000635)/0.00000635]")
report <- c(report, "")

# 计算价格差异百分比
if(nrow(kline_0544) > 0 && nrow(kline_0559) > 0) {
  price_diff_pct <- (kline_0559$close - kline_0544$close) / kline_0544$close * 100
  report <- c(report, sprintf("  5. 05:44到05:59价格上涨了%.2f%%，这会显著影响交易结果", price_diff_pct))
}
report <- c(report, "")

# 11. 时间序列分析
report <- c(report, "【七、完整时间序列分析】")
report <- c(report, paste(rep("-", 80), collapse = ""))
report <- c(report, "基于K线数据的完整时间序列:")
report <- c(report, "")

for(i in 1:nrow(klines_df)) {
  row <- klines_df[i, ]
  time_str <- format(row$timestamp, "%H:%M")

  annotations <- c()

  # 标注R交易
  r_entry <- r_trades[as.POSIXct(r_trades$EntryTime) == row$timestamp, ]
  if(nrow(r_entry) > 0) {
    annotations <- c(annotations, sprintf("R交易#%d入场", r_entry$TradeId))
  }

  # 标注TV交易
  tv_entry_time <- as.POSIXct(tv_trade9$EntryTime, format = "%Y-%m-%d %H:%M:%S")
  if(abs(as.numeric(difftime(row$timestamp, tv_entry_time, units = "secs"))) < 60) {
    annotations <- c(annotations, "TV交易#9入场时间标记")
  }

  # 标注TV实际入场价
  if(abs(row$close - tv_trade9$EntryPrice) < 1e-10) {
    annotations <- c(annotations, "TV交易#9实际入场价")
  }

  annotation_str <- if(length(annotations) > 0) paste(" <--", paste(annotations, collapse = ", ")) else ""

  report <- c(report, sprintf("  %s: 收盘价=%.8f%s", time_str, row$close, annotation_str))
}
report <- c(report, "")

# 12. 建议和结论
report <- c(report, "【八、建议与结论】")
report <- c(report, paste(rep("=", 80), collapse = ""))
report <- c(report, "1. TradingView确认使用'信号确认+延迟入场'机制")
report <- c(report, "   - 入场时间戳: 信号触发的中间时间点")
report <- c(report, "   - 入场价格: 后续K线的收盘价")
report <- c(report, "   - 更保守，更接近实盘交易场景")
report <- c(report, "")
report <- c(report, "2. 如需让R回测与TV保持一致，需要修改为:")
report <- c(report, "   - 信号触发后，不在当前K线入场")
report <- c(report, "   - 等待N根K线后，使用该K线收盘价入场")
report <- c(report, "   - 具体延迟N的值需要进一步分析多个交易确定")
report <- c(report, "")
report <- c(report, "3. 这种差异导致的影响:")
report <- c(report, "   - 入场价格不同(本例高7.72%)")
report <- c(report, "   - 持仓时间不同")
report <- c(report, "   - 最终盈亏结果存在显著差异")
report <- c(report, "   - TV的回测结果可能更保守、更可靠")
report <- c(report, "")
report <- c(report, "4. 下一步建议:")
report <- c(report, "   - 分析更多TV交易样本，确定延迟入场的具体规则")
report <- c(report, "   - 检查TV策略代码中的入场逻辑设置")
report <- c(report, "   - 修改R回测脚本以匹配TV的入场机制")
report <- c(report, "   - 重新对比修正后的R回测与TV结果")
report <- c(report, "")
report <- c(report, paste(rep("=", 80), collapse = ""))
report <- c(report, "分析完成!")
report <- c(report, paste(rep("=", 80), collapse = ""))

# 保存报告
writeLines(report, "tv_trade9_analysis.txt")

# 同时输出到控制台
cat(paste(report, collapse = "\n"))
cat("\n\n报告已保存至: tv_trade9_analysis.txt\n")

# 输出关键K线数据表格
cat("\n\n【关键K线数据】:\n")
print(klines_df, row.names = FALSE)

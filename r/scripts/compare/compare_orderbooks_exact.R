# ============================================================================
# 精确转换TradingView Excel时间并与R回测结果进行秒级比对
# ============================================================================

# 加载必要的库
library(data.table)
library(lubridate)

# Excel日期转换函数 (精确处理Excel序列号)
excel_to_datetime <- function(excel_serial) {
  # Excel日期从1900-01-01开始计数
  # 注意：Excel有1900年闰年bug，对于1900-03-01之前的日期需要减1天
  # 但我们的数据都是2023年之后，不受影响

  # Excel的起点是1899-12-30（因为1900-01-01是第1天）
  origin <- as.POSIXct("1899-12-30 00:00:00", tz="UTC")

  # 转换：整数部分是天数，小数部分是一天内的时间
  datetime <- origin + (excel_serial * 86400)  # 86400秒/天

  return(datetime)
}

# 读取数据
cat("读取数据文件...\n")
tv_raw <- fread("data/tradingview_trades.csv", encoding = "UTF-8")
r_trades <- fread("outputs/trades_tradingview_aligned.csv")

cat("TradingView原始数据行数:", nrow(tv_raw), "\n")
cat("R回测数据行数:", nrow(r_trades), "\n\n")

# ============================================================================
# 1. 转换TradingView数据
# ============================================================================
cat("转换TradingView Excel时间格式...\n")

# 转换时间列
tv_raw$DateTime_Converted <- excel_to_datetime(tv_raw$`日期/时间`)

# 提取交易信息（每2行是一笔交易：进场+出场）
tv_entries <- tv_raw[tv_raw$`类型` == "多头进场", ]
tv_exits <- tv_raw[tv_raw$`类型` == "多头出场", ]

# 构建TradingView交易表
tv_trades <- data.table(
  TV_TradeId = tv_entries$`交易 #`,
  TV_EntryTime = tv_entries$DateTime_Converted,
  TV_EntryPrice = tv_entries$`价格 USDT`,
  TV_ExitTime = tv_exits$DateTime_Converted,
  TV_ExitPrice = tv_exits$`价格 USDT`,
  TV_PnLPercent = tv_exits$`净损益 %`,
  TV_PnLAmount = tv_exits$`净损益 USDT`
)

cat("TradingView交易数量:", nrow(tv_trades), "\n")
cat("TradingView时间范围:",
    as.character(min(tv_trades$TV_EntryTime)), "至",
    as.character(max(tv_trades$TV_ExitTime)), "\n\n")

# ============================================================================
# 2. 转换R回测数据时间格式
# ============================================================================
cat("转换R回测时间格式...\n")

# R的时间已经是字符串格式，转换为POSIXct
r_trades$R_EntryTime <- as.POSIXct(r_trades$EntryTime, tz="UTC")
r_trades$R_ExitTime <- as.POSIXct(r_trades$ExitTime, tz="UTC")

cat("R回测交易数量:", nrow(r_trades), "\n")
cat("R回测时间范围:",
    as.character(min(r_trades$R_EntryTime)), "至",
    as.character(max(r_trades$R_ExitTime)), "\n\n")

# ============================================================================
# 3. 关键时间对比
# ============================================================================
cat("========================================\n")
cat("关键发现：时间范围不匹配分析\n")
cat("========================================\n")

cat("\nTradingView:\n")
cat("  第一笔交易入场时间:", as.character(tv_trades$TV_EntryTime[1]), "\n")
cat("  第一笔交易出场时间:", as.character(tv_trades$TV_ExitTime[1]), "\n")
cat("  第一笔交易价格: 入场=", tv_trades$TV_EntryPrice[1],
    ", 出场=", tv_trades$TV_ExitPrice[1], "\n")

cat("\nR回测:\n")
cat("  第一笔交易入场时间:", as.character(r_trades$R_EntryTime[1]), "\n")
cat("  第一笔交易出场时间:", as.character(r_trades$R_ExitTime[1]), "\n")
cat("  第一笔交易价格: 入场=", r_trades$EntryPrice[1],
    ", 出场=", r_trades$ExitPrice[1], "\n\n")

# 计算时间差
time_diff_days <- as.numeric(difftime(r_trades$R_EntryTime[1],
                                       tv_trades$TV_EntryTime[1],
                                       units = "days"))
cat("第一笔交易时间差:", round(time_diff_days, 2), "天\n\n")

# ============================================================================
# 4. 逐笔交易匹配 (基于序号)
# ============================================================================
cat("执行逐笔交易匹配...\n")

# 确保两个数据集长度一致
n_trades <- min(nrow(tv_trades), nrow(r_trades))
cat("可匹配的交易数量:", n_trades, "\n\n")

# 合并数据
comparison <- data.table(
  TradeNum = 1:n_trades,

  # TradingView数据
  TV_EntryTime = tv_trades$TV_EntryTime[1:n_trades],
  TV_ExitTime = tv_trades$TV_ExitTime[1:n_trades],
  TV_EntryPrice = tv_trades$TV_EntryPrice[1:n_trades],
  TV_ExitPrice = tv_trades$TV_ExitPrice[1:n_trades],
  TV_PnLPercent = tv_trades$TV_PnLPercent[1:n_trades],

  # R回测数据
  R_EntryTime = r_trades$R_EntryTime[1:n_trades],
  R_ExitTime = r_trades$R_ExitTime[1:n_trades],
  R_EntryPrice = r_trades$EntryPrice[1:n_trades],
  R_ExitPrice = r_trades$ExitPrice[1:n_trades],
  R_PnLPercent = as.numeric(gsub("%", "", r_trades$PnLPercent[1:n_trades]))
)

# ============================================================================
# 5. 计算差异指标
# ============================================================================
cat("计算差异指标...\n")

comparison[, `:=`(
  # 时间差异（秒）
  EntryTimeDiff_Sec = as.numeric(difftime(R_EntryTime, TV_EntryTime, units = "secs")),
  ExitTimeDiff_Sec = as.numeric(difftime(R_ExitTime, TV_ExitTime, units = "secs")),

  # 价格差异（百分比）
  EntryPriceDiff_Pct = (R_EntryPrice - TV_EntryPrice) / TV_EntryPrice * 100,
  ExitPriceDiff_Pct = (R_ExitPrice - TV_ExitPrice) / TV_ExitPrice * 100,

  # 盈亏差异
  PnLDiff_Pct = R_PnLPercent - TV_PnLPercent
)]

# 匹配度评分
comparison[, MatchQuality := ifelse(
  abs(EntryTimeDiff_Sec) < 60 & abs(ExitTimeDiff_Sec) < 60 &
    abs(EntryPriceDiff_Pct) < 1 & abs(ExitPriceDiff_Pct) < 1, "优秀",
  ifelse(
    abs(EntryTimeDiff_Sec) < 300 & abs(ExitTimeDiff_Sec) < 300 &
      abs(EntryPriceDiff_Pct) < 5 & abs(ExitPriceDiff_Pct) < 5, "良好",
    ifelse(
      abs(EntryTimeDiff_Sec) < 3600 & abs(ExitTimeDiff_Sec) < 3600 &
        abs(EntryPriceDiff_Pct) < 10 & abs(ExitPriceDiff_Pct) < 10, "一般",
      "差"
    )
  )
)]

# ============================================================================
# 6. 保存详细对比表
# ============================================================================
cat("保存详细对比结果...\n")

output_file <- "outputs/tv_r_exact_comparison.csv"
fwrite(comparison, output_file, row.names = FALSE)
cat("已保存详细对比表:", output_file, "\n\n")

# ============================================================================
# 7. 生成统计汇总
# ============================================================================
cat("生成统计汇总报告...\n")

summary_text <- paste0(
  "========================================\n",
  "TradingView vs R回测 时间差异汇总统计\n",
  "========================================\n\n",

  "总交易数量: ", n_trades, "\n\n",

  "【入场时间差异】\n",
  "  平均差异: ", round(mean(comparison$EntryTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  中位数差异: ", round(median(comparison$EntryTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  最小差异: ", round(min(comparison$EntryTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  最大差异: ", round(max(comparison$EntryTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  标准差: ", round(sd(comparison$EntryTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n\n",

  "【出场时间差异】\n",
  "  平均差异: ", round(mean(comparison$ExitTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  中位数差异: ", round(median(comparison$ExitTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  最小差异: ", round(min(comparison$ExitTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  最大差异: ", round(max(comparison$ExitTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n",
  "  ���准差: ", round(sd(comparison$ExitTimeDiff_Sec, na.rm=TRUE), 2), " 秒\n\n",

  "【入场价格差异】\n",
  "  平均差异: ", round(mean(comparison$EntryPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  中位数差异: ", round(median(comparison$EntryPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  最小差异: ", round(min(comparison$EntryPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  最大差异: ", round(max(comparison$EntryPriceDiff_Pct, na.rm=TRUE), 4), " %\n\n",

  "【出场价格差异】\n",
  "  平均差异: ", round(mean(comparison$ExitPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  中位数差异: ", round(median(comparison$ExitPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  最小差异: ", round(min(comparison$ExitPriceDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  最大差异: ", round(max(comparison$ExitPriceDiff_Pct, na.rm=TRUE), 4), " %\n\n",

  "【盈亏差异】\n",
  "  平均差异: ", round(mean(comparison$PnLDiff_Pct, na.rm=TRUE), 4), " %\n",
  "  中位数差异: ", round(median(comparison$PnLDiff_Pct, na.rm=TRUE), 4), " %\n\n",

  "【匹配质量分布】\n",
  paste(capture.output(table(comparison$MatchQuality)), collapse="\n"), "\n\n",

  "【时间差异规律检测】\n",
  "入场时间差异是否恒定: ",
  ifelse(sd(comparison$EntryTimeDiff_Sec, na.rm=TRUE) < 1, "是（偏移量恒定）", "否（有波动）"), "\n",
  "出场时间差异是否恒定: ",
  ifelse(sd(comparison$ExitTimeDiff_Sec, na.rm=TRUE) < 1, "是（偏移量恒定）", "否（有波动）"), "\n\n",

  "【数据起点差异分析】\n",
  "TradingView首笔交易: ", as.character(tv_trades$TV_EntryTime[1]), "\n",
  "R回测首笔交易: ", as.character(r_trades$R_EntryTime[1]), "\n",
  "相差天数: ", round(time_diff_days, 2), " 天\n",
  "可能原因:\n",
  "  1. 数据源起始日期不同\n",
  "  2. K线数据对齐问题\n",
  "  3. 策略初始化条件不同\n",
  "  4. 交易所数据可用性差异\n\n"
)

summary_file <- "time_diff_summary.txt"
writeLines(summary_text, summary_file, useBytes = TRUE)
cat(summary_text)
cat("\n已保存汇总报告:", summary_file, "\n\n")

# ============================================================================
# 8. 时间差异可视化数据
# ============================================================================
cat("生成时间差异分布数据...\n")

# 按交易顺序的时间差异
time_diff_plot <- data.table(
  TradeNum = 1:n_trades,
  EntryTimeDiff_Min = comparison$EntryTimeDiff_Sec / 60,
  ExitTimeDiff_Min = comparison$ExitTimeDiff_Sec / 60
)

plot_file <- "outputs/time_diff_plot_data.csv"
fwrite(time_diff_plot, plot_file)
cat("已保存时间差异可视化数据:", plot_file, "\n\n")

# ============================================================================
# 9. 异常交易识别
# ============================================================================
cat("识别异常交易...\n")

# 找出时间差异超过1小时的交易
abnormal_trades <- comparison[abs(EntryTimeDiff_Sec) > 3600 | abs(ExitTimeDiff_Sec) > 3600]

if (nrow(abnormal_trades) > 0) {
  cat("发现", nrow(abnormal_trades), "笔时间差异超过1小时的异常交易:\n")
  print(abnormal_trades[, .(TradeNum,
                            TV_EntryTime, R_EntryTime, EntryTimeDiff_Sec,
                            TV_ExitTime, R_ExitTime, ExitTimeDiff_Sec)])

  abnormal_file <- "outputs/abnormal_trades.csv"
  fwrite(abnormal_trades, abnormal_file)
  cat("\n已保存异常交易列表:", abnormal_file, "\n")
} else {
  cat("未发现时间差异超过1小时的异常交易\n")
}

cat("\n========================================\n")
cat("分析完成！\n")
cat("========================================\n")

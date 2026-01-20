# ============================================================================
# 数据完整性分析报告
# ============================================================================

library(data.table)

# 读取数据
tv_raw <- fread("data/tradingview_trades.csv", encoding = "UTF-8")
r_trades <- fread("outputs/trades_tradingview_aligned.csv")

# Excel转换函数
excel_to_datetime <- function(excel_serial) {
  origin <- as.POSIXct("1899-12-30 00:00:00", tz="UTC")
  datetime <- origin + (excel_serial * 86400)
  return(datetime)
}

# 转换时间
tv_raw$DateTime_Converted <- excel_to_datetime(tv_raw$`日期/时间`)

# 提取交易
tv_entries <- tv_raw[tv_raw$`类型` == "多头进场", ]
tv_exits <- tv_raw[tv_raw$`类型` == "多头出场", ]

# 构建TradingView交易表
tv_trades <- data.table(
  TradeId = tv_entries$`交易 #`,
  EntryTime = tv_entries$DateTime_Converted,
  EntryPrice = tv_entries$`价格 USDT`,
  ExitTime = tv_exits$DateTime_Converted,
  ExitPrice = tv_exits$`价格 USDT`,
  PnL = tv_exits$`净损益 %`
)

# 转换R时间
r_trades$R_EntryTime <- as.POSIXct(r_trades$EntryTime, tz="UTC")
r_trades$R_ExitTime <- as.POSIXct(r_trades$ExitTime, tz="UTC")

# ============================================================================
# 生成报告
# ============================================================================

report <- paste0(
  "========================================\n",
  "数据完整性与对齐问题分析报告\n",
  "========================================\n\n",

  "【数据规模对比】\n",
  "TradingView交易数��: ", nrow(tv_trades), " 笔\n",
  "R回测交易数量: ", nrow(r_trades), " 笔\n",
  "数据完整性: ", round(nrow(tv_trades)/nrow(r_trades)*100, 2), "%\n\n",

  "【时间范围对比】\n",
  "TradingView:\n",
  "  开始时间: ", as.character(min(tv_trades$EntryTime)), "\n",
  "  结束时间: ", as.character(max(tv_trades$ExitTime)), "\n",
  "  时间跨度: ", round(as.numeric(difftime(max(tv_trades$ExitTime),
                                           min(tv_trades$EntryTime),
                                           units="days")), 2), " 天\n\n",

  "R回测:\n",
  "  开始时间: ", as.character(min(r_trades$R_EntryTime)), "\n",
  "  结束时间: ", as.character(max(r_trades$R_ExitTime)), "\n",
  "  时间跨度: ", round(as.numeric(difftime(max(r_trades$R_ExitTime),
                                           min(r_trades$R_EntryTime),
                                           units="days")), 2), " 天\n\n",

  "时间起点差异: ", round(as.numeric(difftime(r_trades$R_EntryTime[1],
                                             tv_trades$EntryTime[1],
                                             units="days")), 2), " 天\n\n",

  "【TradingView数据详情】\n",
  "交易ID: ", paste(tv_trades$TradeId, collapse=", "), "\n",
  "第一笔交易:\n",
  "  入场: ", as.character(tv_trades$EntryTime[1]),
  " @ ", sprintf("%.8f", tv_trades$EntryPrice[1]), "\n",
  "  出场: ", as.character(tv_trades$ExitTime[1]),
  " @ ", sprintf("%.8f", tv_trades$ExitPrice[1]), "\n",
  "  盈亏: ", tv_trades$PnL[1], "%\n\n",

  "最后一笔交易:\n",
  "  入场: ", as.character(tv_trades$EntryTime[nrow(tv_trades)]),
  " @ ", sprintf("%.8f", tv_trades$EntryPrice[nrow(tv_trades)]), "\n",
  "  出场: ", as.character(tv_trades$ExitTime[nrow(tv_trades)]),
  " @ ", sprintf("%.8f", tv_trades$ExitPrice[nrow(tv_trades)]), "\n",
  "  盈亏: ", tv_trades$PnL[nrow(tv_trades)], "%\n\n",

  "【R回测数据详情】\n",
  "第一笔交易:\n",
  "  入场: ", as.character(r_trades$R_EntryTime[1]),
  " @ ", sprintf("%.8f", r_trades$EntryPrice[1]), "\n",
  "  出场: ", as.character(r_trades$R_ExitTime[1]),
  " @ ", sprintf("%.8f", r_trades$ExitPrice[1]), "\n",
  "  盈亏: ", r_trades$PnLPercent[1], "\n\n",

  "最后一笔交易:\n",
  "  入场: ", as.character(r_trades$R_EntryTime[nrow(r_trades)]),
  " @ ", sprintf("%.8f", r_trades$EntryPrice[nrow(r_trades)]), "\n",
  "  出场: ", as.character(r_trades$R_ExitTime[nrow(r_trades)]),
  " @ ", sprintf("%.8f", r_trades$ExitPrice[nrow(r_trades)]), "\n",
  "  盈亏: ", r_trades$PnLPercent[nrow(r_trades)], "\n\n",

  "【关键问题诊断】\n\n",

  "1. 数据不完整问题:\n",
  "   TradingView导出的CSV只包含9笔交易，而R回测有165笔交易。\n",
  "   这说明TradingView的导出功能可能:\n",
  "   - 被限制了导出行数\n",
  "   - 只导出了部分时间段的数据\n",
  "   - 需要手动翻页导出\n\n",

  "2. 时间起点不一致:\n",
  "   - TradingView从 ", as.character(min(tv_trades$EntryTime)), " 开始\n",
  "   - R回测从 ", as.character(min(r_trades$R_EntryTime)), " 开始\n",
  "   - 相差约3天，可能原因:\n",
  "     a) 数据源不同（不同交易所或不同数据提供商）\n",
  "     b) K线数据起始时间不同\n",
  "     c) 策略启动条件不同\n",
  "     d) TradingView使用的历史数据有限\n\n",

  "3. 价格差异巨大:\n",
  "   第一笔交易价格:\n",
  "   - TV入场: ", sprintf("%.8f", tv_trades$EntryPrice[1]),
  " vs R入场: ", sprintf("%.8f", r_trades$EntryPrice[1]), "\n",
  "   - 差异: ", round((r_trades$EntryPrice[1] - tv_trades$EntryPrice[1]) /
                      tv_trades$EntryPrice[1] * 100, 2), "%\n",
  "   这说明两个系统的交易信号触发时机完全不同。\n\n",

  "【建议】\n\n",
  "1. 重新导出TradingView数据:\n",
  "   - 确保导出完整的交易列表（165笔）\n",
  "   - 检查TradingView是否有导出限制\n",
  "   - 尝试分批导出或使用API\n\n",

  "2. 数据对齐策略:\n",
  "   由于时间和价格都存在巨大差异，建议:\n",
  "   - 使用基于价格和盈亏特征的匹配（而非时间）\n",
  "   - 寻找相似的盈亏模式序列\n",
  "   - 使用动态时间规整(DTW)算法匹配交易序列\n\n",

  "3. 根本原因调查:\n",
  "   - 确认TradingView和R使用的是同一个币种和交易对\n",
  "   - 确认K线数据来源是否一致\n",
  "   - 检查策略参数是否完全相同\n",
  "   - 验证交易时间框架(timeframe)是否一致\n\n"
)

cat(report)
writeLines(report, "data_completeness_report.txt", useBytes = TRUE)
cat("\n已保存报告: data_completeness_report.txt\n")

# 保存详细的TV交易列表
tv_detail <- data.table(
  TradeId = tv_trades$TradeId,
  EntryTime = as.character(tv_trades$EntryTime),
  EntryPrice = sprintf("%.10f", tv_trades$EntryPrice),
  ExitTime = as.character(tv_trades$ExitTime),
  ExitPrice = sprintf("%.10f", tv_trades$ExitPrice),
  PnL = tv_trades$PnL,
  Duration_Hours = round(as.numeric(difftime(tv_trades$ExitTime,
                                             tv_trades$EntryTime,
                                             units="hours")), 2)
)

fwrite(tv_detail, "outputs/tv_trades_detailed.csv")
cat("已保存TradingView详细交易列表: outputs/tv_trades_detailed.csv\n")

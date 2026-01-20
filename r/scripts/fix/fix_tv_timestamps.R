# 修复TradingView时间戳格式
# 将所有时间统一为K线结束时间(XX:XX:59.999)
# 2025-10-27

cat("\n================================================================================\n")
cat("修复TradingView时间戳格式\n")
cat("================================================================================\n\n")

# 读取原始TV数据
tv <- read.csv("outputs/tv_trades_detailed.csv", stringsAsFactors = FALSE)

cat("原始数据:\n")
cat(rep("=", 100), "\n", sep="")
for (i in 1:nrow(tv)) {
  cat(sprintf("%d. 入场=%s | 出场=%s\n", i, tv$EntryTime[i], tv$ExitTime[i]))
}
cat("\n")

# 规范化时间戳函数
normalize_timestamp <- function(timestamp_str) {
  # 如果缺少时分秒,补充00:00:00
  if (!grepl(":", timestamp_str)) {
    timestamp_str <- paste0(timestamp_str, " 00:00:00")
  }

  # 解析时间
  dt <- as.POSIXct(timestamp_str, tz="UTC")

  # 检查秒数
  secs <- as.numeric(format(dt, "%S"))
  subsecs <- dt - floor(as.numeric(dt))

  # 如果是XX:XX:00.000003格式(K线开始),转换为K线结束(+14分59秒)
  if (secs == 0 && subsecs < 0.001) {
    # 这是K线开始时间,加14分59秒得到结束时间
    dt <- dt + 14 * 60 + 59
  }

  # 格式化为标准格式
  result <- format(dt, "%Y-%m-%d %H:%M:%S")

  return(result)
}

# 应用修复
tv$EntryTime_Fixed <- sapply(tv$EntryTime, normalize_timestamp)
tv$ExitTime_Fixed <- sapply(tv$ExitTime, normalize_timestamp)

cat("修复后数据:\n")
cat(rep("=", 100), "\n", sep="")
for (i in 1:nrow(tv)) {
  cat(sprintf("%d. 入场=%s -> %s\n", i, tv$EntryTime[i], tv$EntryTime_Fixed[i]))
  cat(sprintf("   出场=%s -> %s\n", tv$ExitTime[i], tv$ExitTime_Fixed[i]))
  cat("\n")
}

# 保存修复后的数据
tv_fixed <- data.frame(
  TradeId = tv$TradeId,
  EntryTime = tv$EntryTime_Fixed,
  EntryPrice = tv$EntryPrice,
  ExitTime = tv$ExitTime_Fixed,
  ExitPrice = tv$ExitPrice,
  PnL = tv$PnL,
  stringsAsFactors = FALSE
)

write.csv(tv_fixed, "outputs/tv_trades_fixed.csv", row.names = FALSE)
cat("OK 修复后数据已保存: tv_trades_fixed.csv\n\n")

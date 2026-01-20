# ============================================================================
# 测试修复: 禁止同一根K线的出场+入场
# ============================================================================
# 目标: 验证添加 i != lastExitBar 检查后, R交易数量是否与TV一致
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
})

cat("\n============================================================\n")
cat("测试修复方案: 禁止同一根K线的出场+入场\n")
cat("============================================================\n\n")

# ============================================================================
# 测试1: 原版引擎 (有问题)
# ============================================================================

cat("测试1: 运行原版引擎 (未修复)\n")
cat("------------------------------------------------------------\n")

source("backtest_tradingview_aligned.R")
load("data/liaochu.RData")
data <- cryptodata[["PEPEUSDT_15m"]]

result_original <- backtest_tradingview_aligned(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE
)

cat(sprintf("交易数量: %d笔\n", result_original$TradeCount))
cat(sprintf("被忽略信号: %d个\n", result_original$IgnoredSignalCount))
cat(sprintf("收益率: %.2f%%\n", result_original$ReturnPercent))
cat(sprintf("胜率: %.2f%%\n\n", result_original$WinRate))

# ============================================================================
# 测试2: 修复版引擎
# ============================================================================

cat("测试2: 运行修复版引擎 (添加 i != lastExitBar)\n")
cat("------------------------------------------------------------\n")

# 创建修复版的回测函数 (临时内联版本)
backtest_fixed <- function(data,
                           lookbackDays,
                           minDropPercent,
                           takeProfitPercent,
                           stopLossPercent,
                           initialCapital = 10000,
                           feeRate = 0.00075,
                           processOnClose = TRUE,
                           verbose = FALSE,
                           logIgnoredSignals = TRUE) {

  start_time <- Sys.time()

  # 生成信号
  signals <- generate_drop_signals(data, lookbackDays, minDropPercent)
  signalCount <- sum(signals, na.rm = TRUE)

  if (signalCount == 0) {
    return(list(TradeCount = 0, IgnoredSignalCount = 0, ReturnPercent = 0, WinRate = 0))
  }

  # 预提取数据
  n <- nrow(data)
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])
  close_vec <- as.numeric(data[, "Close"])
  open_vec <- as.numeric(data[, "Open"])
  timestamps <- index(data)

  # 初始化
  capital <- initialCapital
  position <- 0
  inPosition <- FALSE
  entryPrice <- 0
  entryBar <- 0
  entryCapital <- 0
  totalFees <- 0
  lastExitBar <- 0  # 关键变量

  tpCount <- 0
  slCount <- 0
  bothTriggerCount <- 0

  trades <- list()
  tradeId <- 0

  ignoredSignals <- list()
  ignoredCount <- 0

  capitalCurve <- numeric(n)

  # 逐K线模拟
  for (i in 1:n) {

    # 阶段1: 检查出场
    if (inPosition && i > entryBar) {
      currentHigh <- high_vec[i]
      currentLow <- low_vec[i]
      currentClose <- close_vec[i]
      currentOpen <- open_vec[i]

      if (!is.na(currentHigh) && !is.na(currentLow) && !is.na(currentClose) && entryPrice > 0) {
        tpPrice <- entryPrice * (1 + takeProfitPercent / 100)
        slPrice <- entryPrice * (1 - stopLossPercent / 100)

        hitTP <- currentHigh >= tpPrice
        hitSL <- currentLow <= slPrice

        exitTriggered <- FALSE
        exitPrice <- NA
        exitReason <- ""

        if (hitTP && hitSL) {
          bothTriggerCount <- bothTriggerCount + 1
          if (!is.na(currentOpen)) {
            if (currentClose >= currentOpen) {
              exitPrice <- currentClose
              exitReason <- "TP_first_in_both"
              tpCount <- tpCount + 1
            } else {
              exitPrice <- currentClose
              exitReason <- "SL_first_in_both"
              slCount <- slCount + 1
            }
          } else {
            exitPrice <- currentClose
            exitReason <- "TP_default_in_both"
            tpCount <- tpCount + 1
          }
          exitTriggered <- TRUE
        } else if (hitTP) {
          exitPrice <- currentClose
          exitReason <- "TP"
          tpCount <- tpCount + 1
          exitTriggered <- TRUE
        } else if (hitSL) {
          exitPrice <- currentClose
          exitReason <- "SL"
          slCount <- slCount + 1
          exitTriggered <- TRUE
        }

        if (exitTriggered) {
          exitCapitalBefore <- position * exitPrice
          exitFee <- exitCapitalBefore * feeRate
          exitCapitalAfter <- exitCapitalBefore - exitFee

          pnlPercent <- ((exitPrice - entryPrice) / entryPrice) * 100
          pnlAmount <- exitCapitalAfter - entryCapital

          capital <- exitCapitalAfter
          totalFees <- totalFees + exitFee

          tradeId <- tradeId + 1
          trades[[tradeId]] <- list(
            TradeId = tradeId,
            EntryBar = entryBar,
            EntryTime = as.character(timestamps[entryBar]),
            EntryPrice = entryPrice,
            ExitBar = i,
            ExitTime = as.character(timestamps[i]),
            ExitPrice = exitPrice,
            ExitReason = exitReason,
            Position = position,
            PnLPercent = pnlPercent,
            PnLAmount = pnlAmount,
            EntryFee = entryFee,
            ExitFee = exitFee,
            TotalFee = entryFee + exitFee,
            HoldingBars = i - entryBar
          )

          position <- 0
          inPosition <- FALSE
          entryPrice <- 0
          entryBar <- 0
          entryCapital <- 0
          lastExitBar <- i  # 记录出场位置
        }
      }
    }

    # 阶段2: 检查入场 (FIX 修复: 添加 i != lastExitBar)
    # 🆕 添加日志: 记录被同一K线规则拒绝的信号
    if (signals[i] && !inPosition && i == lastExitBar) {
      if (logIgnoredSignals) {
        ignoredCount <- ignoredCount + 1
        ignoredSignals[[ignoredCount]] <- list(
          Bar = i,
          Timestamp = as.character(timestamps[i]),
          Reason = "同一根K线已执行出场操作"
        )
      }
    }

    if (signals[i] && !inPosition && i != lastExitBar) {  # FIX 关键修复
      if (processOnClose) {
        entryPrice <- close_vec[i]
        entryBar <- i
      } else {
        if (i < n) {
          entryPrice <- open_vec[i + 1]
          entryBar <- i + 1
        } else {
          if (logIgnoredSignals) {
            ignoredCount <- ignoredCount + 1
            ignoredSignals[[ignoredCount]] <- list(
              Bar = i,
              Timestamp = as.character(timestamps[i]),
              Reason = "最后一根K线，无法下一根开盘入场"
            )
          }
          next
        }
      }

      if (is.na(entryPrice) || entryPrice <= 0) {
        if (logIgnoredSignals) {
          ignoredCount <- ignoredCount + 1
          ignoredSignals[[ignoredCount]] <- list(
            Bar = i,
            Timestamp = as.character(timestamps[i]),
            Reason = sprintf("入场价格无效: %.8f", entryPrice)
          )
        }
        next
      }

      entryFee <- capital * feeRate
      entryCapital <- capital - entryFee

      position <- entryCapital / entryPrice
      capital <- 0
      inPosition <- TRUE
      totalFees <- totalFees + entryFee
    }

    # 阶段3: 记录净值
    if (inPosition && !is.na(close_vec[i]) && close_vec[i] > 0) {
      capitalCurve[i] <- position * close_vec[i]
    } else {
      capitalCurve[i] <- capital
    }
  }

  # 处理未平仓
  if (inPosition && position > 0) {
    finalPrice <- close_vec[n]
    if (!is.na(finalPrice) && finalPrice > 0 && entryPrice > 0) {
      finalCapitalBefore <- position * finalPrice
      finalFee <- finalCapitalBefore * feeRate
      finalCapitalAfter <- finalCapitalBefore - finalFee

      finalPnL <- ((finalPrice - entryPrice) / entryPrice) * 100
      finalPnLAmount <- finalCapitalAfter - entryCapital

      capital <- finalCapitalAfter
      totalFees <- totalFees + finalFee

      tradeId <- tradeId + 1
      trades[[tradeId]] <- list(
        TradeId = tradeId,
        EntryBar = entryBar,
        EntryTime = as.character(timestamps[entryBar]),
        EntryPrice = entryPrice,
        ExitBar = n,
        ExitTime = as.character(timestamps[n]),
        ExitPrice = finalPrice,
        ExitReason = "ForceClose",
        Position = position,
        PnLPercent = finalPnL,
        PnLAmount = finalPnLAmount,
        EntryFee = 0,
        ExitFee = finalFee,
        TotalFee = finalFee,
        HoldingBars = n - entryBar
      )
    }
    position <- 0
    inPosition <- FALSE
  }

  tradeCount <- length(trades)
  if (tradeCount == 0) {
    return(list(
      SignalCount = signalCount,
      TradeCount = 0,
      IgnoredSignalCount = ignoredCount,
      ReturnPercent = 0,
      WinRate = 0,
      Trades = list(),
      IgnoredSignals = ignoredSignals
    ))
  }

  finalCapital <- capital
  returnPercent <- ((finalCapital - initialCapital) / initialCapital) * 100

  pnls <- sapply(trades, function(t) t$PnLPercent)
  winRate <- sum(pnls > 0) / length(pnls) * 100

  return(list(
    SignalCount = signalCount,
    TradeCount = tradeCount,
    IgnoredSignalCount = ignoredCount,
    FinalCapital = finalCapital,
    ReturnPercent = returnPercent,
    WinRate = winRate,
    TPCount = tpCount,
    SLCount = slCount,
    Trades = trades,
    IgnoredSignals = ignoredSignals
  ))
}

# 运行修复版
result_fixed <- backtest_fixed(
  data = data,
  lookbackDays = 3,
  minDropPercent = 20,
  takeProfitPercent = 10,
  stopLossPercent = 10,
  initialCapital = 10000,
  feeRate = 0.00075,
  processOnClose = TRUE,
  verbose = FALSE,
  logIgnoredSignals = TRUE
)

cat(sprintf("交易数量: %d笔\n", result_fixed$TradeCount))
cat(sprintf("被忽略信号: %d个\n", result_fixed$IgnoredSignalCount))
cat(sprintf("收益率: %.2f%%\n", result_fixed$ReturnPercent))
cat(sprintf("胜率: %.2f%%\n\n", result_fixed$WinRate))

# 检查被忽略的信号
if (result_fixed$IgnoredSignalCount > 0) {
  cat("被忽略的信号详情:\n")
  for (sig in result_fixed$IgnoredSignals) {
    if (sig$Reason == "同一根K线已执行出场操作") {
      cat(sprintf("  Bar %d (%s): %s\n", sig$Bar, sig$Timestamp, sig$Reason))
    }
  }
  cat("\n")
}

# ============================================================================
# 对比结果
# ============================================================================

cat("============================================================\n")
cat("结果对比\n")
cat("============================================================\n\n")

tv_trades <- read.csv("outputs/tv_trades_fixed.csv", stringsAsFactors = FALSE)

comparison <- data.frame(
  指标 = c("交易数量", "被忽略信号", "收益率(%)", "胜率(%)"),
  原版R = c(
    result_original$TradeCount,
    result_original$IgnoredSignalCount,
    round(result_original$ReturnPercent, 2),
    round(result_original$WinRate, 2)
  ),
  修复版R = c(
    result_fixed$TradeCount,
    result_fixed$IgnoredSignalCount,
    round(result_fixed$ReturnPercent, 2),
    round(result_fixed$WinRate, 2)
  ),
  TradingView = c(
    nrow(tv_trades),
    NA,
    NA,
    100.00
  ),
  stringsAsFactors = FALSE
)

print(comparison)
cat("\n")

# 验证结果
cat("============================================================\n")
cat("验证结果\n")
cat("============================================================\n\n")

if (result_fixed$TradeCount == nrow(tv_trades)) {
  cat("OK 成功! 修复版R的交易数量与TradingView完全一致!\n")
  cat(sprintf("   都是 %d笔交易\n\n", result_fixed$TradeCount))

  # 导出修复版交易记录
  trades_df <- do.call(rbind, lapply(result_fixed$Trades, function(trade) {
    data.frame(
      TradeId = trade$TradeId,
      EntryTime = trade$EntryTime,
      EntryPrice = sprintf("%.8f", trade$EntryPrice),
      ExitTime = trade$ExitTime,
      ExitPrice = sprintf("%.8f", trade$ExitPrice),
      ExitReason = trade$ExitReason,
      HoldingBars = trade$HoldingBars,
      PnLPercent = sprintf("%.2f", trade$PnLPercent),
      stringsAsFactors = FALSE
    )
  }))

  output_file <- "outputs/r_backtest_trades_fixed.csv"
  write.csv(trades_df, output_file, row.names = FALSE)
  cat(sprintf("修复版交易记录已保存: %s\n\n", output_file))

} else {
  cat("FAIL 仍有差异!\n")
  cat(sprintf("   修复版R: %d笔\n", result_fixed$TradeCount))
  cat(sprintf("   TradingView: %d笔\n", nrow(tv_trades)))
  cat(sprintf("   差异: %d笔\n\n", result_fixed$TradeCount - nrow(tv_trades)))
}

cat("同一K线拒绝入场的情况:\n")
same_bar_rejections <- 0
if (result_fixed$IgnoredSignalCount > 0) {
  for (sig in result_fixed$IgnoredSignals) {
    if (sig$Reason == "同一根K线已执行出场操作") {
      same_bar_rejections <- same_bar_rejections + 1
    }
  }
}
cat(sprintf("  共 %d次被拒绝 (应该是2次: 2023-08-18和2025-10-11)\n", same_bar_rejections))

if (same_bar_rejections == 2) {
  cat("  OK 正确! 成功拦截了2次同一K线的重复入场\n")
} else {
  cat(sprintf("  WARN 预期2次, 实际%d次\n", same_bar_rejections))
}

cat("\n测试完成!\n")

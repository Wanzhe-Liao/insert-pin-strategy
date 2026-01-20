# ============================================================================
# TradingView对齐版R回测引擎
# ============================================================================
#
# 版本: 2.0
# 创建日期: 2025-10-27
# 作者: Claude Code
#
# 对齐目标：
# - 支持两种出场模型（见 `backtest_tradingview_aligned()` 的 `exitMode` 参数）：
#   - exitMode="close"（默认）：Close 触发 + Close 成交价（对齐 `三日暴跌接针策略_R对齐版`）
#   - exitMode="tradingview"：High/Low 盘中触发 + 精确 TP/SL 成交价（更接近 TradingView 的 `strategy.exit` 行为）
#
# 当前实现关键点：
# 1. 【持仓管理】严格实现"一次只一个持仓"
# 2. 【入场时机】对齐 process_orders_on_close=true（默认在信号K线收盘价入场）
# 3. 【出场】由 exitMode 决定触发与成交价模型（默认 close）
# 4. 【出场同K线同时触发】仅在 exitMode="tradingview" 下可能出现；用K线方向近似推断触发顺序（阳线→TP优先，阴线→SL优先）
# 5. 【信号生成】支持两种窗口口径：
#    - includeCurrentBar=TRUE（默认）：包含当前K线（对齐 `ta.highest(high, lookbackBars)`）
#    - includeCurrentBar=FALSE：排除当前K线（对齐 `ta.highest(high, lookbackBars)[1]`）
# 6. 【手续费】按成交额收取（默认 0.075%），入场/出场各一次
# 7. 【详细日志】可选记录所有被忽略的信号（用于调试）
#
# ============================================================================

# 依赖包
suppressMessages({
  if (!require("xts", quietly = TRUE)) install.packages("xts")
  if (!require("data.table", quietly = TRUE)) install.packages("data.table")
  if (!require("RcppRoll", quietly = TRUE)) install.packages("RcppRoll")

  library(xts)
  library(data.table)
  library(RcppRoll)
})

# ============================================================================
# 辅助函数
# ============================================================================

#' 检测时间框架
#' @param xts_data xts对象
#' @return 时间框架分钟数
detect_timeframe_minutes <- function(xts_data) {
  if (nrow(xts_data) < 2) return(NA)

  n_samples <- min(100, nrow(xts_data) - 1)
  time_diffs <- as.numeric(difftime(
    index(xts_data)[2:(n_samples+1)],
    index(xts_data)[1:n_samples],
    units = "mins"
  ))

  tf_minutes <- median(time_diffs, na.rm = TRUE)
  return(round(tf_minutes))
}

#' 转换天数为K线数量
#' @param days 天数
#' @param tf_minutes 时间框架分钟数
#' @return K线数量
days_to_bars <- function(days, tf_minutes) {
  bars_per_day <- 1440 / tf_minutes  # 1440分钟/天
  return(as.integer(days * bars_per_day))
}

# --- Volatility helpers (used by normalized signal modes) --------------------
calc_true_range <- function(high_vec, low_vec, close_vec) {
  stopifnot(length(high_vec) == length(low_vec), length(low_vec) == length(close_vec))

  prev_close <- c(close_vec[1], close_vec[-length(close_vec)])
  pmax(
    high_vec - low_vec,
    abs(high_vec - prev_close),
    abs(low_vec - prev_close),
    na.rm = TRUE
  )
}

calc_atr_wilder <- function(tr_vec, atrLength) {
  atrLength <- as.integer(atrLength)
  if (atrLength < 1) stop("atrLength must be >= 1")

  n <- length(tr_vec)
  if (n < atrLength) return(rep(NA_real_, n))

  atr <- rep(NA_real_, n)
  atr[atrLength] <- mean(tr_vec[1:atrLength], na.rm = TRUE)
  if (atrLength + 1 <= n) {
    for (i in (atrLength + 1):n) {
      atr[i] <- (atr[i - 1] * (atrLength - 1) + tr_vec[i]) / atrLength
    }
  }

  atr
}

# ============================================================================
# 信号生成函数（对齐TradingView的ta.highest()）
# ============================================================================

#' 生成交易信号（向量化，C++加速）
#'
#' 规则（对齐 Pine Script）：
#' 1. 计算过去 N 根K线的最高价（可选：是否包含当前K线）
#' 2. 当前K线的最低价与窗口最高价比较
#' 3. 如果跌幅 >= minDropPercent，产生买入信号
#'
#' Pine Script等价代码：
#' ```pine
#' lookbackBars = input.int(...)
#' // 默认（排除当前K线）：
#' highestHighPrev = ta.highest(high, lookbackBars)[1]
#' percentDrop = (highestHighPrev - low) / highestHighPrev * 100
#'
#' // 可选（包含当前K线）：
#' highestHigh = ta.highest(high, lookbackBars)
#' percentDrop = (highestHigh - low) / highestHigh * 100
#' buySignal = percentDrop >= minDropPercent
#' ```
#'
#' @param data xts数据
#' @param lookbackDays 回看K线数量（历史遗留命名：不是天数）
#' @param minDropPercent 最小跌幅百分比
#' @param includeCurrentBar 是否包含当前K线（默认TRUE）
#' @return 逻辑向量，TRUE表示买入信号
generate_drop_signals <- function(data,
                                  lookbackDays,
                                  minDropPercent,
                                  includeCurrentBar = TRUE,
                                  signalMode = c("absolute", "atr"),
                                  atrLength = 14) {
  signalMode <- match.arg(signalMode)
  n <- nrow(data)

  # WARN 关键修复：Pine Script的命名混淆
  # 虽然变量名叫"lookbackDays"，但Pine Script实际将其当作K线数量使用！
  # Pine: ta.highest(high, lookbackDays) 其中lookbackDays=3 表示3根K线，不是3天
  # 所以R也直接使用输入的数字，不做天数转换
  lookbackBars <- lookbackDays  # 直接使用，不转换

  # 边界检查
  if (n < lookbackBars + 1) {
    return(rep(FALSE, n))
  }

  # 提取价格向量（性能优化）
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])

  # 使用RcppRoll计算滚动最高价（C++级别加速）
  # align="right" 表示窗口包含当前位置（是否排除当前K线由 includeCurrentBar 决定）
  window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)

  if (!isTRUE(includeCurrentBar)) {
    # 排除当前K线：对齐 Pine 的 ta.highest(...)[1]
    window_high <- c(NA, window_high[-length(window_high)])
  }

  # 向量化计算跌幅
  if (identical(signalMode, "atr")) {
    close_vec <- as.numeric(data[, "Close"])
    tr_vec <- calc_true_range(high_vec, low_vec, close_vec)
    atr_vec <- calc_atr_wilder(tr_vec, atrLength = atrLength)

    drop_atr <- (window_high - low_vec) / atr_vec
    signals <- !is.na(drop_atr) & !is.na(window_high) & is.finite(drop_atr) & (atr_vec > 0) & (drop_atr >= minDropPercent)
    return(signals)
  }

  drop_percent <- (window_high - low_vec) / window_high * 100

  # 生成信号
  signals <- !is.na(drop_percent) & (drop_percent >= minDropPercent)

  return(signals)
}

# ============================================================================
# TradingView对齐版回测引擎
# ============================================================================

#' TradingView对齐版回测函数
#'
#' 关键特性：
#' 1. 严格的持仓管理：一次只允许1个持仓
#' 2. 支持两种出场模型（见 `exitMode`）：
#'    - close（默认）：Close触发 + Close成交价
#'    - tradingview：High/Low盘中触发 + 精确TP/SL成交价
#' 3. 可选记录被忽略的信号（用于调试）
#' 4. 输出交易明细与性能统计
#'
#' @param data xts数据（必须包含Open, High, Low, Close）
#' @param lookbackDays 回看K线数量（历史遗留命名：不是天数）
#' @param minDropPercent 最小跌幅百分比（如20表示20%）
#' @param takeProfitPercent 止盈百分比（如10表示10%）
#' @param stopLossPercent 止损百分比（如10表示10%）
#' @param initialCapital 初始资金
#' @param feeRate 手续费率（如0.00075表示0.075%）
#' @param processOnClose 是否在收盘时执行订单（对齐Pine Script的process_orders_on_close）
#' @param verbose 是否输出详细日志
#' @param logIgnoredSignals 是否记录被忽略的信号
#' @param includeCurrentBar 信号窗口是否包含当前K线（默认TRUE）
#' @param exitMode 出场模式：`tradingview`（High/Low盘中触发 + 精确TP/SL价成交）或 `close`（Close触发 + Close价成交）
#'
#' @return 回测结果列表
backtest_tradingview_aligned <- function(data,
                                        lookbackDays,
                                        minDropPercent,
                                        takeProfitPercent,
                                        stopLossPercent,
                                        initialCapital = 10000,
                                        feeRate = 0.00075,
                                        processOnClose = TRUE,
                                        verbose = FALSE,
                                        logIgnoredSignals = TRUE,
                                        includeCurrentBar = TRUE,
                                        exitMode = c("close", "tradingview"),
                                        signalMode = c("absolute", "atr"),
                                        atrLength = 14) {

  exitMode <- match.arg(exitMode)
  signalMode <- match.arg(signalMode)

  # 开始计时
  start_time <- Sys.time()

  # ========== 数据验证 ==========
  if (nrow(data) < 10) {
    return(list(
      Symbol = NA,
      SignalCount = 0,
      TradeCount = 0,
      IgnoredSignalCount = 0,
      FinalCapital = NA,
      ReturnPercent = NA,
      WinRate = NA,
      MaxDrawdown = NA,
      TotalFees = 0,
      TPCount = 0,
      SLCount = 0,
      BothTriggerCount = 0,
      Trades = list(),
      IgnoredSignals = list(),
      Error = "数据行数不足"
    ))
  }

  # ========== 生成信号 ==========
  signals <- generate_drop_signals(
    data,
    lookbackDays,
    minDropPercent,
    includeCurrentBar = includeCurrentBar,
    signalMode = signalMode,
    atrLength = atrLength
  )
  signalCount <- sum(signals, na.rm = TRUE)

  if (verbose) {
    cat(sprintf("\n=== TradingView对齐版回测 ===\n"))
    cat(sprintf("数据行数: %d\n", nrow(data)))
    cat(sprintf("信号总数: %d\n", signalCount))
    cat(sprintf("参数: lookback=%d天, drop=%.1f%%, TP=%.1f%%, SL=%.1f%%\n\n",
                lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent))
  }

  if (signalCount == 0) {
    return(list(
      Symbol = NA,
      SignalCount = 0,
      TradeCount = 0,
      IgnoredSignalCount = 0,
      FinalCapital = initialCapital,
      ReturnPercent = 0,
      WinRate = 0,
      MaxDrawdown = 0,
      TotalFees = 0,
      TPCount = 0,
      SLCount = 0,
      BothTriggerCount = 0,
      Trades = list(),
      IgnoredSignals = list(),
      Error = "无信号"
    ))
  }

  # ========== 预提取数据（性能优化） ==========
  n <- nrow(data)
  high_vec <- as.numeric(data[, "High"])
  low_vec <- as.numeric(data[, "Low"])
  close_vec <- as.numeric(data[, "Close"])
  open_vec <- as.numeric(data[, "Open"])
  timestamps <- index(data)

  # ========== 初始化交易状态 ==========
  capital <- initialCapital
  position <- 0           # 当前持仓数量
  inPosition <- FALSE     # 持仓状态（关键：严格的持仓管理）
  entryPrice <- 0
  entryBar <- 0
  entryCapital <- 0
  totalFees <- 0
  lastExitBar <- 0        # 关键修复：记录上次出场位置（防止快速重入场）

  # 统计变量
  tpCount <- 0
  slCount <- 0
  bothTriggerCount <- 0

  # 交易记录
  trades <- list()
  tradeId <- 0

  # 被忽略的信号记录
  ignoredSignals <- list()
  ignoredCount <- 0

  # 净值曲线
  capitalCurve <- numeric(n)

  # ========== 逐K线模拟交易 ==========
  for (i in 1:n) {

    # TradingView / Pine Script: process_orders_on_close=true ʱ��
    # entry �����ж�ʹ�õ��� "bar ��ʼ" ��ʱ��ĳֲ�״̬��
    # ��ʹͬһ��K�����ȳ������볡��Pine �ڵ�ǰ bar ��Ҳ�������
    # �因此�� i �� bar ��ʼ�ڳֲ�״̬ʱ����¼ signals[i] Ϊ "ignored"��
    wasInPosition <- inPosition
    if (isTRUE(wasInPosition) && isTRUE(signals[i]) && isTRUE(logIgnoredSignals)) {
      ignoredCount <- ignoredCount + 1
      ignoredSignals[[ignoredCount]] <- list(
        Bar = i,
        Timestamp = as.character(timestamps[i]),
        Reason = "�ڳֲ�״̬�£��źű����ԣ�TradingView ����һ��ֻһ���ֲ�"
      )
    }

    # ========================================
    # 阶段1: 检查出场条件（优先处理）
    # ========================================
    # FIX 修复：将出场检查移到入场之前
    # TradingView在process_orders_on_close=true时：
    # 1. 先处理止盈止损出场
    # 2. 再检查新的入场信号
    # 这样允许在同一根K线内先出场再入场
    if (inPosition && i > entryBar) {
      # 关键：等待至少1根K线后才检查出场

      currentHigh <- high_vec[i]
      currentLow <- low_vec[i]
      currentClose <- close_vec[i]
      currentOpen <- open_vec[i]

      # 验证价格有效性
      if (!is.na(currentHigh) && !is.na(currentLow) &&
          !is.na(currentClose) && entryPrice > 0) {

        # 计算止盈止损价格
        tpPrice <- entryPrice * (1 + takeProfitPercent / 100)
        slPrice <- entryPrice * (1 - stopLossPercent / 100)

        if (exitMode == "tradingview") {
          # TradingView 常见：使用 High/Low 判断是否触发 TP/SL（盘中触发）
          hitTP <- currentHigh >= tpPrice
          hitSL <- currentLow <= slPrice
        } else {
          # Close 模式：仅使用 Close 判断是否触发（用于与“R对齐版”Pine手动close逻辑对照）
          hitTP <- currentClose >= tpPrice
          hitSL <- currentClose <= slPrice
        }

        exitTriggered <- FALSE
        exitPrice <- NA
        exitReason <- ""

        if (hitTP && hitSL) {
          # 同时触发止盈和止损
          bothTriggerCount <- bothTriggerCount + 1

          # 判断K线方向来决定哪个先触发
          if (!is.na(currentOpen)) {
            if (currentClose >= currentOpen) {
              # 阳线：止盈优先
              exitPrice <- if (exitMode == "tradingview") tpPrice else currentClose
              exitReason <- "TP_first_in_both"
              tpCount <- tpCount + 1
            } else {
              # 阴线：止损优先
              exitPrice <- if (exitMode == "tradingview") slPrice else currentClose
              exitReason <- "SL_first_in_both"
              slCount <- slCount + 1
            }
          } else {
            # 无法判断K线方向，默认止盈优先
            exitPrice <- if (exitMode == "tradingview") tpPrice else currentClose
            exitReason <- "TP_default_in_both"
            tpCount <- tpCount + 1
          }
          exitTriggered <- TRUE

        } else if (hitTP) {
          # 仅触发止盈
          exitPrice <- if (exitMode == "tradingview") tpPrice else currentClose
          exitReason <- "TP"
          tpCount <- tpCount + 1
          exitTriggered <- TRUE

        } else if (hitSL) {
          # 仅触发止损
          exitPrice <- if (exitMode == "tradingview") slPrice else currentClose
          exitReason <- "SL"
          slCount <- slCount + 1
          exitTriggered <- TRUE
        }

        # 执行出场
        if (exitTriggered) {
          # 计算手续费
          exitCapitalBefore <- position * exitPrice
          exitFee <- exitCapitalBefore * feeRate
          exitCapitalAfter <- exitCapitalBefore - exitFee

          # 计算盈亏
          pnlPercent <- ((exitPrice - entryPrice) / entryPrice) * 100
          pnlAmount <- exitCapitalAfter - entryCapital

          # 更新资金
          capital <- exitCapitalAfter
          totalFees <- totalFees + exitFee

          # 记录交易
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

          if (verbose) {
            cat(sprintf("[出场] Bar=%d, 时间=%s, 价格=%.8f, 原因=%s, 盈亏=%.2f%%, 金额=%.2f, 手续费=%.4f\n",
                        i, as.character(timestamps[i]), exitPrice, exitReason,
                        pnlPercent, pnlAmount, entryFee + exitFee))
          }

          # 重置持仓状态
          position <- 0
          inPosition <- FALSE
          entryPrice <- 0
          entryBar <- 0
          entryCapital <- 0
          lastExitBar <- i
        }
      }
    }

    # ========================================
    # 阶段2: 检查入场信号
    # ========================================
    if (signals[i] && !inPosition && i != lastExitBar) {
      entryLogAlready <- FALSE
      # FIX 关键修复：允许同一K线检测到信号（即使刚出场）
      # 但如果同一K线刚出场，延迟到下一根K线入场
      # 这样对齐TradingView的行为：在检测信号的下一根K线收盘时入场

      # 确定入场价格（对齐Pine Script的process_orders_on_close）
      if (i == lastExitBar) {
        # 同一K线刚出场，延迟到下一根K线收盘入场
        if (i < n) {
          entryPrice <- close_vec[i + 1]
          entryBar <- i + 1
        } else {
          # 最后一根K线，无法入场
          if (logIgnoredSignals) {
            ignoredCount <- ignoredCount + 1
            ignoredSignals[[ignoredCount]] <- list(
              Bar = i,
              Timestamp = as.character(timestamps[i]),
              Reason = "最后一根K线，同K线出场无法下一根入场"
            )
          }
          next
        }
      } else if (processOnClose) {
        # 正常情况：在当前K线收盘时入场
        entryPrice <- close_vec[i]
        entryBar <- i
      } else {
        # processOnClose=false：在下一根K线开盘时执行
        if (i < n) {
          entryPrice <- open_vec[i + 1]
          entryBar <- i + 1
        } else {
          # 最后一根K线，无法入场
          if (logIgnoredSignals) {
            ignoredCount <- ignoredCount + 1
            ignoredSignals[[ignoredCount]] <- list(
              Bar = i,
              Timestamp = as.character(timestamps[i]),
              Reason = "最后一根K线，无法下一根开盘入场"
            )
          }
          entryLogAlready <- TRUE
          entryPrice <- NA_real_
          entryBar <- i
        }
      }

      # 验证入场价格有效性
      if (is.na(entryPrice) || entryPrice <= 0) {
        if (isTRUE(logIgnoredSignals) && !isTRUE(entryLogAlready)) {
          ignoredCount <- ignoredCount + 1
          ignoredSignals[[ignoredCount]] <- list(
            Bar = i,
            Timestamp = as.character(timestamps[i]),
            Reason = sprintf("入场价格无效: %.8f", entryPrice)
          )
        }
      } else {
        # 计算手续费
        entryFee <- capital * feeRate
        entryCapital <- capital - entryFee

        # 入场
        position <- entryCapital / entryPrice
        capital <- 0
        inPosition <- TRUE
        totalFees <- totalFees + entryFee

        if (verbose) {
          cat(sprintf("[入场] Bar=%d, 时间=%s, 价格=%.8f, 数量=%.2f, 手续费=%.4f\n",
                      entryBar, as.character(timestamps[entryBar]),
                      entryPrice, position, entryFee))
        }
      }

    }

    # ========================================
    # 阶段3: 记录净值曲线
    # ========================================
    if (inPosition && !is.na(close_vec[i]) && close_vec[i] > 0) {
      # 有持仓：使用当前价格计算市值
      capitalCurve[i] <- position * close_vec[i]
    } else {
      # 无持仓：使用现金
      capitalCurve[i] <- capital
    }
  }

  # ========== 处理未平仓的持仓 ==========
  if (inPosition && position > 0) {
    # 使用最后一根K线的收盘价强制平仓
    finalPrice <- close_vec[n]

    if (!is.na(finalPrice) && finalPrice > 0 && entryPrice > 0) {
      # 计算手续费
      finalCapitalBefore <- position * finalPrice
      finalFee <- finalCapitalBefore * feeRate
      finalCapitalAfter <- finalCapitalBefore - finalFee

      # 计算盈亏
      finalPnL <- ((finalPrice - entryPrice) / entryPrice) * 100
      finalPnLAmount <- finalCapitalAfter - entryCapital

      # 更新资金
      capital <- finalCapitalAfter
      totalFees <- totalFees + finalFee

      # 记录交易
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
        EntryFee = 0,  # 入场费已在入场时计算
        ExitFee = finalFee,
        TotalFee = finalFee,
        HoldingBars = n - entryBar
      )

      if (verbose) {
        cat(sprintf("[强制平仓] Bar=%d, 时间=%s, 价格=%.8f, 盈亏=%.2f%%\n",
                    n, as.character(timestamps[n]), finalPrice, finalPnL))
      }
    }

    position <- 0
    inPosition <- FALSE
  }

  # ========== 计算性能指标 ==========

  tradeCount <- length(trades)

  if (tradeCount == 0) {
    return(list(
      Symbol = NA,
      SignalCount = signalCount,
      TradeCount = 0,
      IgnoredSignalCount = ignoredCount,
      FinalCapital = capital,
      ReturnPercent = 0,
      WinRate = 0,
      MaxDrawdown = 0,
      TotalFees = totalFees,
      TPCount = tpCount,
      SLCount = slCount,
      BothTriggerCount = bothTriggerCount,
      Trades = list(),
      IgnoredSignals = ignoredSignals,
      ExecutionTime = as.numeric(difftime(Sys.time(), start_time, units = "secs")),
      Error = "无交易"
    ))
  }

  # 最终资金和收益率
  finalCapital <- capital
  returnPercent <- ((finalCapital - initialCapital) / initialCapital) * 100

  # 胜率
  pnls <- sapply(trades, function(t) t$PnLPercent)
  winRate <- sum(pnls > 0) / length(pnls) * 100

  # 最大回撤
  if (length(capitalCurve) > 0 && any(!is.na(capitalCurve))) {
    peak <- cummax(capitalCurve)
    drawdown <- (capitalCurve - peak) / peak * 100
    maxDrawdown <- min(drawdown, na.rm = TRUE)
  } else {
    maxDrawdown <- 0
  }

  # 平均盈亏
  avgPnL <- mean(pnls, na.rm = TRUE)
  avgWin <- mean(pnls[pnls > 0], na.rm = TRUE)
  avgLoss <- mean(pnls[pnls < 0], na.rm = TRUE)

  # 买入持有收益
  firstClose <- close_vec[1]
  lastClose <- close_vec[n]
  if (!is.na(firstClose) && !is.na(lastClose) && firstClose > 0) {
    bhReturn <- ((lastClose - firstClose) / firstClose) * 100
  } else {
    bhReturn <- NA
  }

  excessReturn <- returnPercent - bhReturn

  # 执行时间
  executionTime <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # ========== 汇总结果 ==========

  result <- list(
    # 基本信息
    Symbol = NA,
    StartTime = as.character(timestamps[1]),
    EndTime = as.character(timestamps[n]),
    DataBars = n,

    # 信号统计
    SignalCount = signalCount,
    TradeCount = tradeCount,
    IgnoredSignalCount = ignoredCount,
    SignalUtilizationRate = (tradeCount / signalCount) * 100,

    # 收益指标
    InitialCapital = initialCapital,
    FinalCapital = finalCapital,
    ReturnPercent = returnPercent,
    BuyHoldReturn = bhReturn,
    ExcessReturn = excessReturn,

    # 交易统计
    WinRate = winRate,
    WinCount = sum(pnls > 0),
    LossCount = sum(pnls <= 0),
    AvgPnL = avgPnL,
    AvgWin = avgWin,
    AvgLoss = avgLoss,
    MaxWin = max(pnls, na.rm = TRUE),
    MaxLoss = min(pnls, na.rm = TRUE),

    # 风险指标
    MaxDrawdown = maxDrawdown,

    # 出场原因统计
    TPCount = tpCount,
    SLCount = slCount,
    BothTriggerCount = bothTriggerCount,

    # 成本
    TotalFees = totalFees,
    AvgFeePerTrade = totalFees / tradeCount,

    # 详细记录
    Trades = trades,
    IgnoredSignals = ignoredSignals,
    CapitalCurve = capitalCurve,

    # 元数据
    ExecutionTime = executionTime,
    Parameters = list(
      lookbackDays = lookbackDays,
      minDropPercent = minDropPercent,
      takeProfitPercent = takeProfitPercent,
      stopLossPercent = stopLossPercent,
      feeRate = feeRate,
      processOnClose = processOnClose,
      includeCurrentBar = includeCurrentBar,
      exitMode = exitMode
    )
  )

  if (verbose) {
    cat(sprintf("\n=== 回测完成 ===\n"))
    cat(sprintf("信号数: %d\n", signalCount))
    cat(sprintf("交易数: %d\n", tradeCount))
    cat(sprintf("被忽略信号: %d (%.1f%%)\n", ignoredCount,
                (ignoredCount / signalCount) * 100))
    cat(sprintf("收益率: %.2f%%\n", returnPercent))
    cat(sprintf("胜率: %.2f%%\n", winRate))
    cat(sprintf("最大回撤: %.2f%%\n", maxDrawdown))
    cat(sprintf("总手续费: %.2f USDT\n", totalFees))
    cat(sprintf("执行时间: %.3f秒\n\n", executionTime))
  }

  return(result)
}

# ============================================================================
# 交易详情格式化函数
# ============================================================================

#' 格式化交易详情为数据框
#' @param result 回测结果
#' @return data.frame
format_trades_df <- function(result) {
  if (length(result$Trades) == 0) {
    return(data.frame())
  }

  trades_df <- do.call(rbind, lapply(result$Trades, function(trade) {
    data.frame(
      TradeId = trade$TradeId,
      EntryTime = trade$EntryTime,
      EntryPrice = sprintf("%.8f", trade$EntryPrice),
      ExitTime = trade$ExitTime,
      ExitPrice = sprintf("%.8f", trade$ExitPrice),
      ExitReason = trade$ExitReason,
      HoldingBars = trade$HoldingBars,
      PnLPercent = sprintf("%.2f%%", trade$PnLPercent),
      PnLAmount = sprintf("%.2f", trade$PnLAmount),
      TotalFee = sprintf("%.4f", trade$TotalFee),
      stringsAsFactors = FALSE
    )
  }))

  return(trades_df)
}

#' 格式化被忽略的信号为数据框
#' @param result 回测结果
#' @return data.frame
format_ignored_signals_df <- function(result) {
  if (length(result$IgnoredSignals) == 0) {
    return(data.frame())
  }

  ignored_df <- do.call(rbind, lapply(result$IgnoredSignals, function(sig) {
    df <- data.frame(
      Bar = sig$Bar,
      Timestamp = sig$Timestamp,
      Reason = sig$Reason,
      stringsAsFactors = FALSE
    )

    # 添加可选字段
    if (!is.null(sig$EntryBar)) {
      df$EntryBar <- sig$EntryBar
      df$EntryPrice <- sprintf("%.8f", sig$EntryPrice)
      df$CurrentPrice <- sprintf("%.8f", sig$CurrentPrice)
      df$UnrealizedPnL <- sprintf("%.2f%%", sig$UnrealizedPnL)
    }

    return(df)
  }))

  return(ignored_df)
}

# ============================================================================
# 性能摘要函数
# ============================================================================

#' 打印回测性能摘要
#' @param result 回测结果
print_performance_summary <- function(result) {
  cat("\n")
  cat("=" %R% 60, "\n")
  cat("TradingView对齐版回测性能摘要\n")
  cat("=" %R% 60, "\n\n")

  cat("时间范围:\n")
  cat(sprintf("  开始: %s\n", result$StartTime))
  cat(sprintf("  结束: %s\n", result$EndTime))
  cat(sprintf("  数据: %d根K线\n\n", result$DataBars))

  cat("参数配置:\n")
  p <- result$Parameters
  cat(sprintf("  回看周期: %d天\n", p$lookbackDays))
  cat(sprintf("  触发跌幅: %.1f%%\n", p$minDropPercent))
  cat(sprintf("  止盈: %.1f%%\n", p$takeProfitPercent))
  cat(sprintf("  止损: %.1f%%\n", p$stopLossPercent))
  cat(sprintf("  手续费: %.3f%%\n\n", p$feeRate * 100))

  cat("信号统计:\n")
  cat(sprintf("  总信号数: %d\n", result$SignalCount))
  cat(sprintf("  成交数: %d\n", result$TradeCount))
  cat(sprintf("  被忽略: %d (%.1f%%)\n", result$IgnoredSignalCount,
              (result$IgnoredSignalCount / result$SignalCount) * 100))
  cat(sprintf("  信号利用率: %.1f%%\n\n", result$SignalUtilizationRate))

  cat("收益指标:\n")
  cat(sprintf("  初始资金: $%.2f\n", result$InitialCapital))
  cat(sprintf("  最终资金: $%.2f\n", result$FinalCapital))
  cat(sprintf("  总收益率: %.2f%%\n", result$ReturnPercent))
  cat(sprintf("  买入持有: %.2f%%\n", result$BuyHoldReturn))
  cat(sprintf("  超额收益: %.2f%%\n\n", result$ExcessReturn))

  cat("交易统计:\n")
  cat(sprintf("  胜率: %.2f%% (%d胜 / %d负)\n",
              result$WinRate, result$WinCount, result$LossCount))
  cat(sprintf("  平均盈亏: %.2f%%\n", result$AvgPnL))
  cat(sprintf("  平均盈利: %.2f%%\n", result$AvgWin))
  cat(sprintf("  平均亏损: %.2f%%\n", result$AvgLoss))
  cat(sprintf("  最大盈利: %.2f%%\n", result$MaxWin))
  cat(sprintf("  最大亏损: %.2f%%\n\n", result$MaxLoss))

  cat("出场原因:\n")
  cat(sprintf("  止盈: %d (%.1f%%)\n", result$TPCount,
              (result$TPCount / result$TradeCount) * 100))
  cat(sprintf("  止损: %d (%.1f%%)\n", result$SLCount,
              (result$SLCount / result$TradeCount) * 100))
  cat(sprintf("  同时触发: %d\n\n", result$BothTriggerCount))

  cat("风险指标:\n")
  cat(sprintf("  最大回撤: %.2f%%\n\n", result$MaxDrawdown))

  cat("成本分析:\n")
  cat(sprintf("  总手续费: $%.2f\n", result$TotalFees))
  cat(sprintf("  平均每笔: $%.4f\n", result$AvgFeePerTrade))
  cat(sprintf("  手续费占收益: %.2f%%\n\n",
              (result$TotalFees / (result$FinalCapital - result$InitialCapital)) * 100))

  cat("执行性能:\n")
  cat(sprintf("  执行时间: %.3f秒\n", result$ExecutionTime))
  cat(sprintf("  处理速度: %.0f K线/秒\n", result$DataBars / result$ExecutionTime))

  cat("\n")
  cat("=" %R% 60, "\n\n")
}

# 修复字符串重复运算符
`%R%` <- function(x, n) paste(rep(x, n), collapse = "")

# ============================================================================
# 使用示例和测试用例
# ============================================================================

if (FALSE) {
  # 示例1: 基本使用
  # -----------------

  # 加载数据
  load(file.path("data", "liaochu.RData"))
  data <- cryptodata[["PEPEUSDT_15m"]]

  # 运行回测
  result <- backtest_tradingview_aligned(
    data = data,
    lookbackDays = 3,
    minDropPercent = 20,
    takeProfitPercent = 10,
    stopLossPercent = 10,
    initialCapital = 10000,
    feeRate = 0.00075,  # 0.075%
    processOnClose = TRUE,  # 对齐Pine Script的process_orders_on_close=true
    verbose = TRUE,
    logIgnoredSignals = TRUE
  )

  # 打印性能摘要
  print_performance_summary(result)

  # 查看交易详情
  trades_df <- format_trades_df(result)
  print(head(trades_df, 20))

  # 查看被忽略的信号
  ignored_df <- format_ignored_signals_df(result)
  print(head(ignored_df, 20))

  # 导出到CSV
  write.csv(trades_df, "trades_tradingview_aligned.csv", row.names = FALSE)
  write.csv(ignored_df, "ignored_signals.csv", row.names = FALSE)

  # 示例2: 对比测试
  # -----------------

  # 加载原版回测函数
  source(file.path("r", "engine", "backtest_final_fixed.R"), encoding = "UTF-8")

  # 运行原版
  result_original <- backtest_strategy_final(
    data = data,
    lookback_days = 3,
    drop_threshold = 0.20,
    take_profit = 0.10,
    stop_loss = 0.10
  )

  # 运行TradingView对齐版
  result_aligned <- backtest_tradingview_aligned(
    data = data,
    lookbackDays = 3,
    minDropPercent = 20,
    takeProfitPercent = 10,
    stopLossPercent = 10
  )

  # 对比结果
  comparison <- data.frame(
    Metric = c("信号数", "交易数", "被忽略信号", "收益率(%)",
               "胜率(%)", "最大回撤(%)", "总手续费"),
    Original = c(
      result_original$Signal_Count,
      result_original$Trade_Count,
      NA,
      round(result_original$Return_Percentage, 2),
      round(result_original$Win_Rate, 2),
      round(result_original$Max_Drawdown, 2),
      round(result_original$Total_Fees, 2)
    ),
    Aligned = c(
      result_aligned$SignalCount,
      result_aligned$TradeCount,
      result_aligned$IgnoredSignalCount,
      round(result_aligned$ReturnPercent, 2),
      round(result_aligned$WinRate, 2),
      round(result_aligned$MaxDrawdown, 2),
      round(result_aligned$TotalFees, 2)
    ),
    stringsAsFactors = FALSE
  )

  comparison$Difference <- comparison$Aligned - comparison$Original
  print(comparison)
}

# ============================================================================
# 模块加载确认
# ============================================================================

cat("\n")
cat("OK TradingView对齐版R回测引擎已加载\n")
cat("\n")
cat("主要函数:\n")
cat("  1. backtest_tradingview_aligned()  - 主回测函数\n")
cat("  2. generate_drop_signals()         - 信号生成\n")
cat("  3. format_trades_df()              - 格式化交易详情\n")
cat("  4. format_ignored_signals_df()     - 格式化被忽略信号\n")
cat("  5. print_performance_summary()     - 打印性能摘要\n")
cat("\n")
cat("关键特性:\n")
cat("  OK 严格的持仓管理（一次只一个持仓）\n")
cat("  OK 出场模式: tradingview(High/Low盘中触发+精确TP/SL价) / close(Close触发+Close价)\n")
cat("  OK 记录所有被忽略的信号\n")
cat("  OK 详细的交易日志和调试信息\n")
cat("\n")
cat("使用方法: 参见文件末尾的示例代码\n")
cat("\n")

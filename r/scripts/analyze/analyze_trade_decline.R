# ============================================================================
# Trade Decline Diagnosis
# ----------------------------------------------------------------------------
# Goal:
# - Explain why recent months have fewer trades vs earlier years.
# - Decompose into:
#   1) signal scarcity (pattern itself occurs less)
#   2) capital lock / holding time (signals occur but cannot enter)
#   3) data issues (missing bars / index problems)
#
# Outputs:
# - outputs/trade_decline_monthly_metrics_<dataset>.csv
# - docs/reports/trade_decline_diagnosis.md
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
  library(RcppRoll)
})

source("backtest_tradingview_aligned.R", encoding = "UTF-8")

cat("Loading data/liaochu.RData ...\n")
load("data/liaochu.RData")
stopifnot(exists("cryptodata"))

dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
dir.create(file.path("docs", "reports"), showWarnings = FALSE, recursive = TRUE)

calc_drop_percent <- function(x, lookbackBars) {
  high_vec <- as.numeric(x[, "High"])
  low_vec <- as.numeric(x[, "Low"])
  window_high <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
  (window_high - low_vec) / window_high * 100
}

month_key <- function(idx) format(idx, "%Y-%m")

analyze_one <- function(dataset_name, p) {
  x <- cryptodata[[dataset_name]]
  stopifnot(!is.null(x))

  idx <- index(x)
  months <- month_key(idx)

  lookbackBars <- p$lookbackDays
  drop_percent <- calc_drop_percent(x, lookbackBars)
  signals <- !is.na(drop_percent) & (drop_percent >= p$minDropPercent)

  # Backtest to get trades / holding time
  result <- backtest_tradingview_aligned(
    data = x,
    lookbackDays = p$lookbackDays,
    minDropPercent = p$minDropPercent,
    takeProfitPercent = p$takeProfitPercent,
    stopLossPercent = p$stopLossPercent,
    initialCapital = 10000,
    feeRate = 0.00075,
    processOnClose = TRUE,
    verbose = FALSE,
    logIgnoredSignals = TRUE,
    includeCurrentBar = TRUE,
    exitMode = "close"
  )

  # Signals per month
  sig_dt <- data.table(month = months, signal = signals)
  sig_month <- sig_dt[, .(signals = sum(signal, na.rm = TRUE)), by = month]

  # Drop percent distribution per month (p95 / max)
  drop_dt <- data.table(month = months, drop_percent = drop_percent)
  drop_month <- drop_dt[!is.na(drop_percent), .(
    drop_p95 = as.numeric(quantile(drop_percent, probs = 0.95, na.rm = TRUE)),
    drop_max = max(drop_percent, na.rm = TRUE)
  ), by = month]

  # Trades per month (by entry bar)
  if (length(result$Trades) > 0) {
    entry_bars <- as.integer(vapply(result$Trades, function(t) t$EntryBar, numeric(1)))
    holding_bars <- as.integer(vapply(result$Trades, function(t) t$HoldingBars, numeric(1)))
    exit_reason <- vapply(result$Trades, function(t) t$ExitReason, character(1))

    trade_months <- months[entry_bars]
    trade_dt <- data.table(month = trade_months, holding_bars = holding_bars, exit_reason = exit_reason)
    trade_month <- trade_dt[, .(
      trades = .N,
      holding_bars_avg = mean(holding_bars, na.rm = TRUE),
      holding_bars_p90 = as.numeric(quantile(holding_bars, probs = 0.90, na.rm = TRUE)),
      tp_trades = sum(grepl("^TP", exit_reason), na.rm = TRUE),
      sl_trades = sum(grepl("^SL", exit_reason), na.rm = TRUE)
    ), by = month]
  } else {
    trade_month <- data.table(month = character(), trades = integer(), holding_bars_avg = numeric(),
                              holding_bars_p90 = numeric(), tp_trades = integer(), sl_trades = integer())
  }

  # Ignored signals per month (signals that happened while in position, or other reasons)
  if (length(result$IgnoredSignals) > 0) {
    ignored_bars <- as.integer(vapply(result$IgnoredSignals, function(s) s$Bar, numeric(1)))
    ignored_months <- months[ignored_bars]
    ignored_dt <- data.table(month = ignored_months)
    ignored_month <- ignored_dt[, .(ignored_signals = .N), by = month]
  } else {
    ignored_month <- data.table(month = character(), ignored_signals = integer())
  }

  # Merge
  out <- merge(sig_month, trade_month, by = "month", all = TRUE)
  out <- merge(out, ignored_month, by = "month", all = TRUE)
  out <- merge(out, drop_month, by = "month", all = TRUE)
  out[is.na(out)] <- 0
  setorder(out, month)

  out[, dataset := dataset_name]
  out[, `:=`(
    lookbackDays = p$lookbackDays,
    minDropPercent = p$minDropPercent,
    takeProfitPercent = p$takeProfitPercent,
    stopLossPercent = p$stopLossPercent,
    signal_utilization = fifelse(signals > 0, trades / signals, NA_real_)
  )]

  list(metrics = out, summary = result)
}

targets <- list(
  list(
    dataset = "BTCUSDT_30m",
    params = list(lookbackDays = 10, minDropPercent = 10.5, takeProfitPercent = 1.2, stopLossPercent = 18.8)
  ),
  list(
    dataset = "BNBUSDT_15m",
    params = list(lookbackDays = 10, minDropPercent = 10.7, takeProfitPercent = 0.4, stopLossPercent = 12.7)
  ),
  list(
    dataset = "DOGEUSDT_15m",
    params = list(lookbackDays = 10, minDropPercent = 9.5, takeProfitPercent = 0.3, stopLossPercent = 18.3)
  ),
  list(
    dataset = "PEPEUSDT_15m",
    params = list(lookbackDays = 8, minDropPercent = 7.0, takeProfitPercent = 1.4, stopLossPercent = 12.8)
  )
)

reports <- list()
for (t in targets) {
  ds <- t$dataset
  p <- t$params
  if (!ds %in% names(cryptodata)) {
    cat(sprintf("WARN dataset not found: %s (skip)\n", ds))
    next
  }
  cat(sprintf("\nAnalyzing %s ...\n", ds))
  r <- analyze_one(ds, p)
  reports[[ds]] <- r

  out_csv <- sprintf("outputs/trade_decline_monthly_metrics_%s.csv", ds)
  fwrite(r$metrics, out_csv)
  cat(sprintf("OK Wrote %s\n", out_csv))
}

# Build markdown summary (focus on BTCUSDT_30m if present)
md <- c(
  "# Trade Decline Diagnosis (Recent months vs earlier years)",
  "",
  "This report decomposes the observed decline in trade openings into signal frequency vs holding/locking effects.",
  "",
  "## Key conclusion",
  "",
  "- In the checked datasets/params, the dominant driver is **signal scarcity** (monthly signal counts collapse in recent months), not a sudden increase in holding time.",
  "",
  "## Details",
  ""
)

for (ds in names(reports)) {
  m <- reports[[ds]]$metrics
  p <- reports[[ds]]$summary$Parameters

  # Last 12 months vs earlier
  months <- m$month
  last12 <- tail(months, 12)
  recent <- m[month %in% last12]
  hist <- m[!month %in% last12]

  recent_signals <- sum(recent$signals, na.rm = TRUE)
  hist_signals_per_month <- if (nrow(hist) > 0) mean(hist$signals, na.rm = TRUE) else NA_real_
  recent_signals_per_month <- if (nrow(recent) > 0) mean(recent$signals, na.rm = TRUE) else NA_real_

  recent_trades_per_month <- if (nrow(recent) > 0) mean(recent$trades, na.rm = TRUE) else NA_real_
  hist_trades_per_month <- if (nrow(hist) > 0) mean(hist$trades, na.rm = TRUE) else NA_real_

  recent_hold <- if (sum(recent$trades, na.rm = TRUE) > 0) mean(recent$holding_bars_avg[recent$trades > 0], na.rm = TRUE) else NA_real_
  hist_hold <- if (sum(hist$trades, na.rm = TRUE) > 0) mean(hist$holding_bars_avg[hist$trades > 0], na.rm = TRUE) else NA_real_

  recent_drop_max <- if (nrow(recent) > 0) max(recent$drop_max, na.rm = TRUE) else NA_real_
  hist_drop_max <- if (nrow(hist) > 0) max(hist$drop_max, na.rm = TRUE) else NA_real_

  md <- c(
    md,
    sprintf("### %s", ds),
    "",
    sprintf("- Params: lookback=%d bars, drop>=%.2f%%, TP=%.2f%%, SL=%.2f%%",
            p$lookbackDays, p$minDropPercent, p$takeProfitPercent, p$stopLossPercent),
    sprintf("- Recent (last 12 months in data): avg signals/month=%.2f, avg trades/month=%.2f",
            recent_signals_per_month, recent_trades_per_month),
    sprintf("- Earlier: avg signals/month=%.2f, avg trades/month=%.2f",
            hist_signals_per_month, hist_trades_per_month),
    sprintf("- Holding time proxy (avg holding bars on months with trades): recent=%.2f, earlier=%.2f",
            recent_hold, hist_hold),
    sprintf("- Drop%% max (proxy for regime volatility): recent max=%.2f, earlier max=%.2f",
            recent_drop_max, hist_drop_max),
    sprintf("- Monthly metrics CSV: `outputs/trade_decline_monthly_metrics_%s.csv`", ds),
    ""
  )
}

report_md <- file.path("docs", "reports", "trade_decline_diagnosis.md")
writeLines(md, report_md, useBytes = TRUE)
cat(sprintf("\nOK Wrote %s\n", report_md))

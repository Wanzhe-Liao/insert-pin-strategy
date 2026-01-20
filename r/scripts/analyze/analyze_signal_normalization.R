# ============================================================================
# Signal Normalization Analysis (handle signal scarcity)
# ----------------------------------------------------------------------------
# Goal:
# - Compare "absolute drop%" signals vs "ATR-normalized drop" signals.
# - Show whether normalization reduces the recent signal collapse.
#
# Outputs:
# - outputs/signal_normalization_monthly_<dataset>.csv
# - docs/reports/signal_normalization_analysis.md
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

month_key <- function(idx) format(idx, "%Y-%m")

calc_window_high <- function(high_vec, lookbackBars, includeCurrentBar) {
  wh <- RcppRoll::roll_max(high_vec, n = lookbackBars, align = "right", fill = NA)
  if (!isTRUE(includeCurrentBar)) {
    wh <- c(NA, wh[-length(wh)])
  }
  wh
}

calc_drop_percent <- function(x, lookbackBars, includeCurrentBar = TRUE) {
  high_vec <- as.numeric(x[, "High"])
  low_vec <- as.numeric(x[, "Low"])
  window_high <- calc_window_high(high_vec, lookbackBars, includeCurrentBar = includeCurrentBar)
  (window_high - low_vec) / window_high * 100
}

calc_drop_atr <- function(x, lookbackBars, includeCurrentBar = TRUE, atrLength = 14) {
  high_vec <- as.numeric(x[, "High"])
  low_vec <- as.numeric(x[, "Low"])
  close_vec <- as.numeric(x[, "Close"])
  window_high <- calc_window_high(high_vec, lookbackBars, includeCurrentBar = includeCurrentBar)

  tr_vec <- calc_true_range(high_vec, low_vec, close_vec)
  atr_vec <- calc_atr_wilder(tr_vec, atrLength = atrLength)

  (window_high - low_vec) / atr_vec
}

calibrate_atr_threshold <- function(drop_atr, base_signals, train_mask) {
  stopifnot(length(drop_atr) == length(base_signals), length(train_mask) == length(base_signals))

  base_n <- sum(base_signals[train_mask], na.rm = TRUE)
  drop_train <- drop_atr[train_mask]
  drop_train <- drop_train[is.finite(drop_train)]

  if (length(drop_train) == 0 || base_n <= 0) return(Inf)
  if (base_n >= length(drop_train)) return(min(drop_train, na.rm = TRUE))

  # Pick a fixed ATR threshold such that training period signal count matches
  # the baseline signal count (by selecting the base_n-th largest drop_atr).
  sorted <- sort(drop_train, decreasing = TRUE)
  sorted[[base_n]]
}

summarize_recent_vs_history <- function(monthly_dt) {
  all_months <- monthly_dt$month
  last12 <- tail(all_months, 12)

  recent <- monthly_dt[month %in% last12]
  hist <- monthly_dt[!month %in% last12]

  list(
    recent_abs = if (nrow(recent) > 0) mean(recent$signals_abs) else NA_real_,
    hist_abs = if (nrow(hist) > 0) mean(hist$signals_abs) else NA_real_,
    recent_atr = if (nrow(recent) > 0) mean(recent$signals_atr) else NA_real_,
    hist_atr = if (nrow(hist) > 0) mean(hist$signals_atr) else NA_real_
  )
}

analyze_one <- function(dataset_name, p, includeCurrentBar = TRUE, atrLength = 14, exitMode = "close") {
  x <- cryptodata[[dataset_name]]
  stopifnot(!is.null(x))

  idx <- index(x)
  months <- month_key(idx)
  lookbackBars <- p$lookbackDays

  # Baseline (absolute drop%)
  drop_percent <- calc_drop_percent(x, lookbackBars, includeCurrentBar = includeCurrentBar)
  signals_abs <- !is.na(drop_percent) & (drop_percent >= p$minDropPercent)

  # ATR-normalized drop and threshold calibrated on "training" (exclude last 12 months)
  drop_atr <- calc_drop_atr(x, lookbackBars, includeCurrentBar = includeCurrentBar, atrLength = atrLength)
  last12 <- tail(unique(months), 12)
  train_mask <- !(months %in% last12)
  atr_threshold <- calibrate_atr_threshold(drop_atr, signals_abs, train_mask = train_mask)

  signals_atr <- is.finite(drop_atr) & (drop_atr >= atr_threshold)

  # Monthly counts
  sig_dt <- data.table(month = months, signals_abs = signals_abs, signals_atr = signals_atr)
  sig_month <- sig_dt[, .(
    signals_abs = sum(signals_abs, na.rm = TRUE),
    signals_atr = sum(signals_atr, na.rm = TRUE)
  ), by = month]
  setorder(sig_month, month)

  out_csv <- sprintf("outputs/signal_normalization_monthly_%s.csv", dataset_name)
  fwrite(sig_month, out_csv)

  # Backtests (trade counts) for a quick sanity check (optional, but useful)
  res_abs <- backtest_tradingview_aligned(
    data = x,
    lookbackDays = p$lookbackDays,
    minDropPercent = p$minDropPercent,
    takeProfitPercent = p$takeProfitPercent,
    stopLossPercent = p$stopLossPercent,
    initialCapital = 10000,
    feeRate = 0.00075,
    processOnClose = TRUE,
    verbose = FALSE,
    logIgnoredSignals = FALSE,
    includeCurrentBar = includeCurrentBar,
    exitMode = exitMode,
    signalMode = "absolute"
  )

  res_atr <- backtest_tradingview_aligned(
    data = x,
    lookbackDays = p$lookbackDays,
    minDropPercent = atr_threshold,
    takeProfitPercent = p$takeProfitPercent,
    stopLossPercent = p$stopLossPercent,
    initialCapital = 10000,
    feeRate = 0.00075,
    processOnClose = TRUE,
    verbose = FALSE,
    logIgnoredSignals = FALSE,
    includeCurrentBar = includeCurrentBar,
    exitMode = exitMode,
    signalMode = "atr",
    atrLength = atrLength
  )

  stats <- summarize_recent_vs_history(sig_month)

  list(
    dataset = dataset_name,
    params = p,
    atrLength = atrLength,
    includeCurrentBar = includeCurrentBar,
    atr_threshold = atr_threshold,
    signals_summary = stats,
    result_abs = res_abs,
    result_atr = res_atr,
    csv = out_csv
  )
}

targets <- list(
  list(
    dataset = "BTCUSDT_30m",
    params = list(lookbackDays = 10, minDropPercent = 10.5, takeProfitPercent = 1.2, stopLossPercent = 18.8)
  ),
  list(
    dataset = "BNBUSDT_15m",
    params = list(lookbackDays = 10, minDropPercent = 10.7, takeProfitPercent = 0.4, stopLossPercent = 12.7)
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
  reports[[ds]] <- analyze_one(ds, p, includeCurrentBar = TRUE, atrLength = 14, exitMode = "close")
  cat(sprintf("OK Wrote %s\n", reports[[ds]]$csv))
}

md <- c(
  "# Signal Normalization Analysis (absolute vs ATR-normalized)",
  "",
  "This report explains one common reason for signal scarcity: **volatility regime change**. If the strategy uses a fixed `drop%` threshold (e.g., 10%), then signals will naturally collapse when the market becomes less volatile.",
  "",
  "We compare:",
  "",
  "- **Absolute drop%**: `(highestHigh - low) / highestHigh * 100 >= minDropPercent`",
  "- **ATR-normalized drop**: `(highestHigh - low) / ATR >= thresholdATR` (threshold is calibrated to match the baseline signal count on the training period)",
  "",
  "Notes:",
  "",
  "- ATR-normalization changes the meaning of the signal: it detects *relative extremes* under the current volatility regime.",
  "- If your goal is specifically to trade only very large absolute crashes, then signal scarcity is expected and not a bug.",
  "",
  "## Results",
  ""
)

for (ds in names(reports)) {
  r <- reports[[ds]]
  p <- r$params
  s <- r$signals_summary

  md <- c(
    md,
    sprintf("### %s", ds),
    "",
    sprintf("- Baseline params: lookback=%d bars, drop>=%.2f%%, TP=%.2f%%, SL=%.2f%%",
            p$lookbackDays, p$minDropPercent, p$takeProfitPercent, p$stopLossPercent),
    sprintf("- ATR config: atrLength=%d, calibrated thresholdATR=%.4f", r$atrLength, r$atr_threshold),
    sprintf("- Signals/month (recent last-12 vs earlier): abs %.2f vs %.2f; atr %.2f vs %.2f",
            s$recent_abs, s$hist_abs, s$recent_atr, s$hist_atr),
    sprintf("- TradeCount (abs vs atr): %d vs %d", r$result_abs$TradeCount, r$result_atr$TradeCount),
    sprintf("- Monthly CSV: `%s`", r$csv),
    ""
  )
}

report_md <- file.path("docs", "reports", "signal_normalization_analysis.md")
writeLines(md, report_md, useBytes = TRUE)
cat(sprintf("\nOK Wrote %s\n", report_md))


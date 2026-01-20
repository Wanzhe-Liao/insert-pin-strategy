# ============================================================================
# Multi-timeframe Walk-Forward (signalMode="atr") + Parameter Optimization
# ----------------------------------------------------------------------------
# Symbols: DOGEUSDT / PEPEUSDT / XRPUSDT
# Timeframes: configurable (default: 5m,15m,30m,1h)
#
# Method (chosen for speed & robustness):
# - Rolling monthly walk-forward
# - Each window: optimize on train months via 2-stage random search, then test on
#   next month (out-of-sample).
#
# Output:
# - <output_dir>/<dataset>_atr_wf_details.csv
# - <output_dir>/<dataset>_atr_wf_summary.md
# - docs/reports/multitimeframe_atr_walkforward_summary.csv
# - docs/reports/multitimeframe_atr_walkforward_summary.md
#
# Data:
# - Uses data/liaochu.RData (object: cryptodata)
# - If DOGE datasets are missing, can auto-download recent DOGEUSDT klines from
#   Binance REST API (cached in data/dogeusdt_klines_cache.RData; ignored by git).
# ============================================================================

suppressMessages({
  if (!require("optparse", quietly = TRUE)) install.packages("optparse")
  if (!require("xts", quietly = TRUE)) install.packages("xts")
  if (!require("data.table", quietly = TRUE)) install.packages("data.table")
  if (!require("RcppRoll", quietly = TRUE)) install.packages("RcppRoll")
  if (!require("httr", quietly = TRUE)) install.packages("httr")
  if (!require("jsonlite", quietly = TRUE)) install.packages("jsonlite")

  library(optparse)
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(httr)
  library(jsonlite)
})

source("backtest_tradingview_aligned.R", encoding = "UTF-8")

option_list <- list(
  make_option(c("--signal_mode"), type = "character", default = "atr",
              help = "Signal mode: atr or absolute [default: %default]"),
  make_option(c("--symbols"), type = "character", default = "DOGEUSDT,PEPEUSDT,XRPUSDT",
              help = "Comma-separated symbols [default: %default]"),
  make_option(c("--timeframes"), type = "character", default = "5m,15m,30m,1h",
              help = "Comma-separated timeframes [default: %default]"),
  make_option(c("--train_months"), type = "integer", default = 12,
              help = "Train window in months [default: %default]"),
  make_option(c("--test_months"), type = "integer", default = 1,
              help = "Test window in months [default: %default]"),
  make_option(c("--last_windows"), type = "integer", default = 12,
              help = "Only run last N windows [default: %default]"),
  make_option(c("--atr_length"), type = "integer", default = 14,
              help = "ATR length for signalMode=atr [default: %default]"),
  make_option(c("--lookback_min"), type = "integer", default = 2,
              help = "Min lookback bars [default: %default]"),
  make_option(c("--lookback_max"), type = "integer", default = 20,
              help = "Max lookback bars [default: %default]"),
  make_option(c("--drop_min"), type = "double", default = 4.0,
              help = "Min drop threshold in ATR units [default: %default]"),
  make_option(c("--drop_max"), type = "double", default = 12.0,
              help = "Max drop threshold in ATR units [default: %default]"),
  make_option(c("--tp_min"), type = "double", default = 1.0,
              help = "Min take profit percent [default: %default]"),
  make_option(c("--tp_max"), type = "double", default = 8.0,
              help = "Max take profit percent [default: %default]"),
  make_option(c("--sl_min"), type = "double", default = 1.0,
              help = "Min stop loss percent [default: %default]"),
  make_option(c("--sl_max"), type = "double", default = 6.0,
              help = "Max stop loss percent [default: %default]"),
  make_option(c("--phase1"), type = "integer", default = 200,
              help = "Random samples phase1 [default: %default]"),
  make_option(c("--phase2"), type = "integer", default = 200,
              help = "Random samples phase2 [default: %default]"),
  make_option(c("--min_trades_train"), type = "integer", default = 10,
              help = "Minimum trades in training to score >0 [default: %default]"),
  make_option(c("--download_missing_doge"), action = "store_true", default = TRUE,
              help = "Auto-download DOGEUSDT if missing [default: %default]"),
  make_option(c("--doge_days"), type = "integer", default = 900,
              help = "Days of DOGE data to download if missing [default: %default]"),
  make_option(c("--binance_sleep"), type = "double", default = 0.15,
              help = "Sleep seconds between Binance requests [default: %default]"),
  make_option(c("--output_dir"), type = "character", default = "walkforward_atr_symbols",
              help = "Output directory [default: %default]")
)

opt <- parse_args(OptionParser(option_list = option_list))

signal_mode <- match.arg(tolower(opt$signal_mode), c("atr", "absolute"))
symbols <- trimws(unlist(strsplit(opt$symbols, ",")))
timeframes <- trimws(unlist(strsplit(opt$timeframes, ",")))

train_months <- opt$train_months
test_months <- opt$test_months
last_windows_default <- opt$last_windows
atr_length <- opt$atr_length

lookback_min <- opt$lookback_min
lookback_max <- opt$lookback_max
drop_min <- opt$drop_min
drop_max <- opt$drop_max
tp_min <- opt$tp_min
tp_max <- opt$tp_max
sl_min <- opt$sl_min
sl_max <- opt$sl_max

phase1_default <- opt$phase1
phase2_default <- opt$phase2
min_trades_train <- opt$min_trades_train

download_missing_doge <- isTRUE(opt$download_missing_doge)
doge_days <- opt$doge_days
binance_sleep <- opt$binance_sleep
output_dir <- opt$output_dir

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path("docs", "reports"), showWarnings = FALSE, recursive = TRUE)

cat("\nMulti-timeframe ATR Walk-Forward\n")
cat(sprintf("- symbols: %s\n", paste(symbols, collapse = ", ")))
cat(sprintf("- timeframes: %s\n", paste(timeframes, collapse = ", ")))
cat(sprintf("- train=%dm test=%dm last_windows=%d\n", train_months, test_months, last_windows_default))
cat(sprintf("- search: lookback[%d,%d], dropATR[%.2f,%.2f], TP%%[%.2f,%.2f], SL%%[%.2f,%.2f]\n",
            lookback_min, lookback_max, drop_min, drop_max, tp_min, tp_max, sl_min, sl_max))
cat(sprintf("- samples: phase1=%d phase2=%d | atrLength=%d\n\n", phase1_default, phase2_default, atr_length))

cat("Loading data/liaochu.RData ...\n")
load("data/liaochu.RData")
stopifnot(exists("cryptodata"))

extract_symbol_tf <- function(dataset_name) {
  parts <- strsplit(dataset_name, "_", fixed = TRUE)[[1]]
  list(symbol = parts[[1]], timeframe = parts[[2]])
}

month_key <- function(idx) format(idx, "%Y-%m")

split_data_by_month <- function(data_xts) {
  dates <- index(data_xts)
  year_month <- format(dates, "%Y-%m")
  unique_months <- unique(year_month)

  month_list <- list()
  for (ym in unique_months) {
    mdata <- data_xts[year_month == ym]
    if (nrow(mdata) > 0) month_list[[ym]] <- mdata
  }
  month_list
}

generate_rolling_windows <- function(month_ids, train_size, test_size) {
  n_months <- length(month_ids)
  windows <- list()
  for (i in 1:(n_months - train_size - test_size + 1)) {
    train_start <- i
    train_end <- i + train_size - 1
    test_start <- train_end + 1
    test_end <- test_start + test_size - 1
    windows[[length(windows) + 1]] <- list(
      window_id = length(windows) + 1,
      train_months = month_ids[train_start:train_end],
      test_months = month_ids[test_start:test_end]
    )
  }
  windows
}

calc_equity_curve <- function(monthly_returns_pct, initial_capital = 10000) {
  capital <- initial_capital
  equity <- numeric(length(monthly_returns_pct))
  for (i in seq_along(monthly_returns_pct)) {
    r <- monthly_returns_pct[[i]] / 100
    capital <- capital * (1 + r)
    equity[[i]] <- capital
  }
  equity
}

calc_max_drawdown <- function(equity_curve) {
  if (length(equity_curve) == 0) return(0)
  peak <- -Inf
  dd <- 0
  for (x in equity_curve) {
    peak <- max(peak, x)
    dd <- min(dd, (x / peak - 1) * 100)
  }
  dd
}

score_result <- function(res) {
  if (is.null(res)) return(0)
  if (!is.finite(res$TradeCount) || res$TradeCount < min_trades_train) return(0)
  if (!is.finite(res$ReturnPercent) || res$ReturnPercent <= 0) return(0)
  if (!is.finite(res$MaxDrawdown) || !is.finite(res$WinRate)) return(0)

  max_return <- 500
  max_trades <- 250
  normalized_return <- min(res$ReturnPercent / max_return, 1.0)
  normalized_winrate <- res$WinRate / 100
  normalized_drawdown_control <- 1 - abs(res$MaxDrawdown) / 100
  normalized_trades <- min(sqrt(res$TradeCount) / sqrt(max_trades), 1.0)

  w_return <- 0.45
  w_drawdown <- 0.30
  w_winrate <- 0.05
  w_trades <- 0.20

  w_return * normalized_return +
    w_drawdown * normalized_drawdown_control +
    w_winrate * normalized_winrate +
    w_trades * normalized_trades
}

rand_round <- function(x, step = 0.05) round(x / step) * step

sample_params <- function(n, phase_seed) {
  set.seed(phase_seed)
  data.table(
    lookback = sample(lookback_min:lookback_max, n, replace = TRUE),
    minDrop = rand_round(runif(n, drop_min, drop_max), step = 0.05),
    TP = rand_round(runif(n, tp_min, tp_max), step = 0.05),
    SL = rand_round(runif(n, sl_min, sl_max), step = 0.05)
  )
}

refine_params <- function(top_dt, n, phase_seed) {
  set.seed(phase_seed)
  out <- data.table(lookback = integer(n), minDrop = numeric(n), TP = numeric(n), SL = numeric(n))
  for (i in 1:n) {
    base <- top_dt[sample(.N, 1)]
    out$lookback[i] <- pmax(lookback_min, pmin(lookback_max, round(base$lookback + rnorm(1, 0, 2))))
    out$minDrop[i] <- rand_round(pmax(drop_min, pmin(drop_max, base$minDrop + rnorm(1, 0, 0.8))), step = 0.05)
    out$TP[i] <- rand_round(pmax(tp_min, pmin(tp_max, base$TP + rnorm(1, 0, 1.0))), step = 0.05)
    out$SL[i] <- rand_round(pmax(sl_min, pmin(sl_max, base$SL + rnorm(1, 0, 1.0))), step = 0.05)
  }
  out
}

eval_params <- function(params_dt, data_xts) {
  out <- vector("list", nrow(params_dt))
  for (i in 1:nrow(params_dt)) {
    p <- params_dt[i]
    res <- tryCatch(
      backtest_tradingview_aligned(
        data = data_xts,
        lookbackDays = p$lookback,
        minDropPercent = p$minDrop,
        takeProfitPercent = p$TP,
        stopLossPercent = p$SL,
        initialCapital = 10000,
        feeRate = 0.00075,
        processOnClose = TRUE,
        verbose = FALSE,
        logIgnoredSignals = FALSE,
        includeCurrentBar = TRUE,
        exitMode = "close",
        signalMode = "atr",
        atrLength = atr_length
      ),
      error = function(e) NULL
    )

    out[[i]] <- data.table(
      lookback = p$lookback,
      minDrop = p$minDrop,
      TP = p$TP,
      SL = p$SL,
      score = score_result(res),
      return_pct = if (!is.null(res)) res$ReturnPercent else NA_real_,
      win_rate = if (!is.null(res)) res$WinRate else NA_real_,
      max_dd = if (!is.null(res)) res$MaxDrawdown else NA_real_,
      trades = if (!is.null(res)) res$TradeCount else NA_integer_,
      signals = if (!is.null(res)) res$SignalCount else NA_integer_
    )
  }
  rbindlist(out, fill = TRUE)
}

optimize_2stage <- function(train_data, phase1_n, phase2_n, seed_base) {
  p1 <- sample_params(phase1_n, phase_seed = seed_base + 1)
  r1 <- eval_params(p1, train_data)
  setorder(r1, -score, -return_pct, max_dd)

  keep_n <- max(10, as.integer(round(nrow(r1) * 0.15)))
  top <- head(r1, keep_n)
  top_pos <- top[score > 0]
  if (nrow(top_pos) >= 3) top <- top_pos

  p2 <- refine_params(top, phase2_n, phase_seed = seed_base + 2)
  r2 <- eval_params(p2, train_data)

  all <- rbindlist(list(r1, r2), fill = TRUE)
  setorder(all, -score, -return_pct, max_dd)
  list(best = all[1], all = all)
}

format_dataset_summary_md <- function(summary_row, detail_file) {
  c(
    sprintf("# ATR Walk-Forward Summary — %s", summary_row$dataset),
    "",
    sprintf("- signalMode: `atr` (atrLength=%d)", summary_row$atrLength),
    sprintf("- train/test: %d/%d months, windows=%d", summary_row$train_months, summary_row$test_months, summary_row$windows),
    sprintf("- cumulative out-of-sample return: %.2f%%", summary_row$cumulative_return_pct),
    sprintf("- max drawdown (OS equity curve): %.2f%%", summary_row$max_drawdown_pct),
    sprintf("- avg monthly return: %.2f%% (sd %.2f%%), Sharpe~%.2f", summary_row$avg_monthly_return_pct, summary_row$sd_monthly_return_pct, summary_row$sharpe_ratio),
    sprintf("- OS months: +%d / -%d / 0=%d", summary_row$pos_months, summary_row$neg_months, summary_row$zero_months),
    "",
    "## Parameter stability",
    "",
    sprintf("- lookback: mean=%.2f sd=%.2f", summary_row$lookback_mean, summary_row$lookback_sd),
    sprintf("- dropATR:  mean=%.2f sd=%.2f", summary_row$dropATR_mean, summary_row$dropATR_sd),
    sprintf("- TP%%:     mean=%.2f sd=%.2f", summary_row$TP_mean, summary_row$TP_sd),
    sprintf("- SL%%:     mean=%.2f sd=%.2f", summary_row$SL_mean, summary_row$SL_sd),
    "",
    sprintf("Details CSV: `%s`", detail_file)
  )
}

run_one_dataset <- function(dataset_name, data_xts, timeframe_cfg, seed_base) {
  tf <- extract_symbol_tf(dataset_name)
  symbol <- tf$symbol
  timeframe <- tf$timeframe

  phase1_n <- timeframe_cfg$phase1
  phase2_n <- timeframe_cfg$phase2
  last_windows <- timeframe_cfg$last_windows

  month_list <- split_data_by_month(data_xts)
  month_ids <- names(month_list)
  windows_all <- generate_rolling_windows(month_ids, train_months, test_months)
  if (length(windows_all) == 0) {
    return(NULL)
  }
  if (!is.null(last_windows) && is.finite(last_windows) && last_windows > 0) {
    windows <- tail(windows_all, min(last_windows, length(windows_all)))
  } else {
    windows <- windows_all
  }

  rows <- list()
  for (w in windows) {
    train_data <- do.call(rbind, lapply(w$train_months, function(m) month_list[[m]]))
    test_data <- do.call(rbind, lapply(w$test_months, function(m) month_list[[m]]))

    opt_start <- Sys.time()
    opt_res <- optimize_2stage(train_data, phase1_n, phase2_n, seed_base = seed_base + w$window_id * 1000)
    opt_secs <- as.numeric(difftime(Sys.time(), opt_start, units = "secs"))
    best <- opt_res$best

    test_bt <- backtest_tradingview_aligned(
      data = test_data,
      lookbackDays = best$lookback,
      minDropPercent = best$minDrop,
      takeProfitPercent = best$TP,
      stopLossPercent = best$SL,
      initialCapital = 10000,
      feeRate = 0.00075,
      processOnClose = TRUE,
      verbose = FALSE,
      logIgnoredSignals = FALSE,
      includeCurrentBar = TRUE,
      exitMode = "close",
      signalMode = "atr",
      atrLength = atr_length
    )

    rows[[length(rows) + 1]] <- data.table(
      window_id = w$window_id,
      train_months = paste(w$train_months, collapse = "|"),
      test_months = paste(w$test_months, collapse = "|"),
      lookback = best$lookback,
      minDrop = best$minDrop,
      TP = best$TP,
      SL = best$SL,
      train_score = best$score,
      train_return_pct = best$return_pct,
      train_win_rate = best$win_rate,
      train_max_dd = best$max_dd,
      train_trades = best$trades,
      test_return_pct = test_bt$ReturnPercent,
      test_win_rate = test_bt$WinRate,
      test_max_dd = test_bt$MaxDrawdown,
      test_trades = test_bt$TradeCount,
      test_signals = test_bt$SignalCount,
      opt_time_secs = opt_secs
    )
  }

  dt <- rbindlist(rows, fill = TRUE)
  setorder(dt, window_id)

  equity <- calc_equity_curve(dt$test_return_pct, initial_capital = 10000)
  cum_return <- (tail(equity, 1) / 10000 - 1) * 100
  max_dd <- calc_max_drawdown(equity)

  mret <- dt$test_return_pct
  avg_m <- mean(mret, na.rm = TRUE)
  sd_m <- sd(mret, na.rm = TRUE)
  sharpe <- if (is.finite(sd_m) && sd_m > 0) (avg_m / sd_m) * sqrt(12) else NA_real_

  summary_row <- data.table(
    dataset = dataset_name,
    symbol = symbol,
    timeframe = timeframe,
    signalMode = "atr",
    atrLength = atr_length,
    train_months = train_months,
    test_months = test_months,
    windows = nrow(dt),
    phase1 = phase1_n,
    phase2 = phase2_n,
    cumulative_return_pct = as.numeric(cum_return),
    max_drawdown_pct = as.numeric(max_dd),
    avg_monthly_return_pct = as.numeric(avg_m),
    sd_monthly_return_pct = as.numeric(sd_m),
    sharpe_ratio = as.numeric(sharpe),
    pos_months = sum(mret > 0, na.rm = TRUE),
    neg_months = sum(mret < 0, na.rm = TRUE),
    zero_months = sum(mret == 0, na.rm = TRUE),
    lookback_mean = mean(dt$lookback, na.rm = TRUE),
    lookback_sd = sd(dt$lookback, na.rm = TRUE),
    dropATR_mean = mean(dt$minDrop, na.rm = TRUE),
    dropATR_sd = sd(dt$minDrop, na.rm = TRUE),
    TP_mean = mean(dt$TP, na.rm = TRUE),
    TP_sd = sd(dt$TP, na.rm = TRUE),
    SL_mean = mean(dt$SL, na.rm = TRUE),
    SL_sd = sd(dt$SL, na.rm = TRUE)
  )

  detail_file <- file.path(output_dir, sprintf("%s_atr_wf_details.csv", dataset_name))
  fwrite(dt, detail_file)

  summary_file <- file.path(output_dir, sprintf("%s_atr_wf_summary.md", dataset_name))
  writeLines(format_dataset_summary_md(summary_row, detail_file), summary_file, useBytes = TRUE)

  list(summary = summary_row, detail_file = detail_file, summary_file = summary_file)
}

interval_to_binance <- function(tf) {
  # Crypto data naming matches Binance intervals for these formats.
  tf
}

download_binance_klines_xts <- function(symbol, interval, start_date, end_date, sleep_secs = 0.15) {
  # Prefer Binance "vision" endpoint (often more reachable than api.binance.com).
  url <- "https://data-api.binance.vision/api/v3/klines"
  limit <- 1000

  # NOTE: milliseconds since epoch exceed 32-bit integer range; keep as numeric
  # and send as character to the API.
  start_ms <- as.numeric(as.POSIXct(start_date, tz = "UTC")) * 1000
  end_ms <- as.numeric(as.POSIXct(end_date, tz = "UTC")) * 1000

  parts <- list()
  next_start <- start_ms

  repeat {
    resp <- NULL
    for (attempt in 1:5) {
      resp <- tryCatch(
        GET(
          url,
          query = list(
            symbol = symbol,
            interval = interval,
            startTime = sprintf("%.0f", next_start),
            endTime = sprintf("%.0f", end_ms),
            limit = limit
          ),
          user_agent("insert-pin-strategy/1.0"),
          timeout(30)
        ),
        error = function(e) e
      )

      if (!inherits(resp, "error")) break
      Sys.sleep(max(1, sleep_secs * attempt * 2))
    }

    if (inherits(resp, "error")) stop(resp)

    if (status_code(resp) == 429) {
      Sys.sleep(max(1, sleep_secs * 5))
      next
    }
    stop_for_status(resp)

    txt <- content(resp, as = "text", encoding = "UTF-8")
    arr <- jsonlite::fromJSON(txt)
    if (length(arr) == 0) break

    dt <- as.data.table(arr)
    parts[[length(parts) + 1]] <- dt

    # closeTime is column 7 (ms). Continue from next ms.
    last_close_ms <- as.numeric(dt[nrow(dt), 7])
    next_start <- last_close_ms + 1
    if (!is.finite(next_start) || next_start >= end_ms) break

    Sys.sleep(sleep_secs)
  }

  if (length(parts) == 0) return(NULL)

  all <- rbindlist(parts, fill = TRUE)
  setnames(all, paste0("V", seq_len(ncol(all))))
  all <- unique(all, by = "V1")
  setorder(all, V1)

  close_time <- as.numeric(all$V7) / 1000
  idx <- as.POSIXct(close_time, origin = "1970-01-01", tz = "UTC")

  x <- xts(
    cbind(
      Open = as.numeric(all$V2),
      High = as.numeric(all$V3),
      Low = as.numeric(all$V4),
      Close = as.numeric(all$V5),
      Volume = as.numeric(all$V6)
    ),
    order.by = idx
  )

  x
}

ensure_doge_data <- function(timeframes_needed) {
  doge_cache <- file.path("data", "dogeusdt_klines_cache.RData")
  doge_list <- list()
  if (file.exists(doge_cache)) {
    cat(sprintf("Loading DOGE cache: %s\n", doge_cache))
    load(doge_cache) # expects doge_list
    if (!exists("doge_list")) doge_list <- list()
  }

  missing_tfs <- timeframes_needed[!paste0("DOGEUSDT_", timeframes_needed) %in% names(cryptodata)]
  missing_tfs <- missing_tfs[!paste0("DOGEUSDT_", missing_tfs) %in% names(doge_list)]
  if (length(missing_tfs) == 0) {
    return(invisible(NULL))
  }

  # Download recent DOGE data for missing timeframes
  # Use end date aligned to existing datasets (max timestamp in current cryptodata).
  any_ds <- names(cryptodata)[[1]]
  end_time <- max(index(cryptodata[[any_ds]]))
  end_date <- as.POSIXct(end_time, tz = "UTC")
  start_date <- as.POSIXct(end_date - doge_days * 86400, tz = "UTC")

  cat(sprintf("Downloading DOGEUSDT klines (%d days): %s -> %s\n",
              doge_days,
              format(start_date, "%Y-%m-%d"),
              format(end_date, "%Y-%m-%d")))

  for (tf in missing_tfs) {
    interval <- interval_to_binance(tf)
    cat(sprintf("  - DOGEUSDT %s ...\n", interval))
    x <- download_binance_klines_xts(
      symbol = "DOGEUSDT",
      interval = interval,
      start_date = start_date,
      end_date = end_date,
      sleep_secs = binance_sleep
    )
    if (is.null(x) || nrow(x) == 0) {
      cat(sprintf("    WARN no data for %s (skip)\n", tf))
      next
    }
    doge_list[[paste0("DOGEUSDT_", tf)]] <- x
    cat(sprintf("    OK rows=%d\n", nrow(x)))
  }

  save(doge_list, file = doge_cache)
  cat(sprintf("OK Saved DOGE cache: %s\n", doge_cache))
}

# Ensure DOGE is available if requested
if (download_missing_doge && ("DOGEUSDT" %in% symbols)) {
  need_tfs <- timeframes
  ensure_doge_data(need_tfs)

  # Merge doge_list into cryptodata
  doge_cache <- file.path("data", "dogeusdt_klines_cache.RData")
  if (file.exists(doge_cache)) {
    load(doge_cache) # loads doge_list
    if (exists("doge_list") && length(doge_list) > 0) {
      for (nm in names(doge_list)) {
        if (!nm %in% names(cryptodata)) cryptodata[[nm]] <- doge_list[[nm]]
      }
    }
  }
}

tf_config <- function(tf) {
  # Heuristic: shorter timeframe => reduce windows/samples to keep runtime bounded.
  if (identical(tf, "5m")) {
    return(list(phase1 = max(80L, as.integer(round(phase1_default * 0.75))),
                phase2 = max(80L, as.integer(round(phase2_default * 0.75))),
                last_windows = max(6L, min(12L, as.integer(round(last_windows_default * 0.75))))))
  }
  list(phase1 = phase1_default, phase2 = phase2_default, last_windows = last_windows_default)
}

datasets <- unlist(lapply(symbols, function(s) paste0(s, "_", timeframes)))
available <- datasets[datasets %in% names(cryptodata)]
missing <- setdiff(datasets, names(cryptodata))

if (length(missing) > 0) {
  cat("\nWARN missing datasets (skip):\n")
  cat(paste0("  - ", missing, collapse = "\n"), "\n")
}

if (length(available) == 0) stop("No datasets available for requested symbols/timeframes.")

all_summaries <- list()
seed_base <- 20260120L

cat("\nRunning datasets:\n")
cat(paste0("  - ", available, collapse = "\n"), "\n\n")

for (ds in available) {
  tf <- extract_symbol_tf(ds)
  cfg <- tf_config(tf$timeframe)
  cat(sprintf("=== %s | phase1=%d phase2=%d last_windows=%d ===\n",
              ds, cfg$phase1, cfg$phase2, cfg$last_windows))

  res <- run_one_dataset(ds, cryptodata[[ds]], cfg, seed_base = seed_base)
  if (is.null(res)) {
    cat("SKIP (not enough months)\n\n")
    next
  }

  all_summaries[[length(all_summaries) + 1]] <- res$summary
  cat(sprintf("OK %s | OOS=%.2f%% | maxDD=%.2f%% | Sharpe=%.2f\n\n",
              ds,
              res$summary$cumulative_return_pct,
              res$summary$max_drawdown_pct,
              res$summary$sharpe_ratio))
}

summary_dt <- rbindlist(all_summaries, fill = TRUE)
if (nrow(summary_dt) == 0) stop("No results produced (all datasets skipped).")

setorder(summary_dt, symbol, -cumulative_return_pct)

summary_csv <- file.path("docs", "reports", "multitimeframe_atr_walkforward_summary.csv")
fwrite(summary_dt, summary_csv)

md <- c(
  "# Multi-timeframe ATR Walk-Forward Summary",
  "",
  sprintf("- symbols: %s", paste(symbols, collapse = ", ")),
  sprintf("- timeframes: %s", paste(timeframes, collapse = ", ")),
  sprintf("- train/test: %d/%d months, last_windows(default)=%d", train_months, test_months, last_windows_default),
  sprintf("- signalMode: `atr` (atrLength=%d)", atr_length),
  sprintf("- search: lookback[%d,%d], dropATR[%.2f,%.2f], TP%%[%.2f,%.2f], SL%%[%.2f,%.2f]",
          lookback_min, lookback_max, drop_min, drop_max, tp_min, tp_max, sl_min, sl_max),
  "",
  "## Results (ranked by cumulative OOS return within each symbol)",
  ""
)

for (s in unique(summary_dt$symbol)) {
  md <- c(md, sprintf("### %s", s), "")
  sdt <- summary_dt[symbol == s]
  for (i in 1:nrow(sdt)) {
    row <- sdt[i]
    md <- c(
      md,
      sprintf("- %s: OOS %.2f%%, maxDD %.2f%%, Sharpe %.2f, windows %d",
              row$timeframe,
              row$cumulative_return_pct,
              row$max_drawdown_pct,
              row$sharpe_ratio,
              row$windows)
    )
  }
  md <- c(md, "")
}

md <- c(md, sprintf("Summary CSV: `%s`", summary_csv))

summary_md <- file.path("docs", "reports", "multitimeframe_atr_walkforward_summary.md")
writeLines(md, summary_md, useBytes = TRUE)

cat("\nDONE\n")
cat(sprintf("Per-dataset results: %s\n", output_dir))
cat(sprintf("Summary: %s\n", summary_md))
cat(sprintf("Summary CSV: %s\n", summary_csv))

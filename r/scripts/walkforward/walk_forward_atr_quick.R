# ============================================================================
# Walk-Forward (ATR-normalized signalMode="atr") - Quick Runner
# ----------------------------------------------------------------------------
# Goal:
# - Run a rolling walk-forward with parameter optimization on the training set,
#   then apply best params to the next test month.
# - Designed for fast iteration (small sample sizes, limited windows).
#
# Output:
# - <output_dir>/<dataset>_atr_wf_details.csv
# - <output_dir>/<dataset>_atr_wf_summary.md
#
# Notes:
# - This optimizes lookback/minDrop(ATR units)/TP%/SL% under signalMode="atr".
# - TP/SL are still percent-based exits; consider ATR-based exits for better
#   consistency under regime shifts.
# ============================================================================

suppressMessages({
  if (!require("optparse", quietly = TRUE)) install.packages("optparse")
  if (!require("xts", quietly = TRUE)) install.packages("xts")
  if (!require("data.table", quietly = TRUE)) install.packages("data.table")
  if (!require("RcppRoll", quietly = TRUE)) install.packages("RcppRoll")
  if (!require("foreach", quietly = TRUE)) install.packages("foreach")
  if (!require("doParallel", quietly = TRUE)) install.packages("doParallel")
  if (!require("httr", quietly = TRUE)) install.packages("httr")
  if (!require("jsonlite", quietly = TRUE)) install.packages("jsonlite")

  library(optparse)
  library(xts)
  library(data.table)
  library(RcppRoll)
  library(foreach)
  library(doParallel)
  library(httr)
  library(jsonlite)
})

option_list <- list(
  make_option(c("-d", "--dataset"), type = "character", default = "BTCUSDT_30m",
              help = "Dataset name (e.g., BTCUSDT_30m) [default: %default]"),
  make_option(c("--update_binance_to"), type = "character", default = "",
              help = "If set (e.g., 2026-01-01), download missing klines from Binance up to this UTC date (inclusive). [default: %default]"),
  make_option(c("--binance_sleep"), type = "double", default = 0.15,
              help = "Sleep seconds between Binance requests [default: %default]"),
  make_option(c("-t", "--train_months"), type = "integer", default = 12,
              help = "Training window size in months [default: %default]"),
  make_option(c("--test_months"), type = "integer", default = 1,
              help = "Test window size in months [default: %default]"),
  make_option(c("-w", "--last_windows"), type = "integer", default = 12,
              help = "Only run the last N windows (keep runtime bounded) [default: %default]"),
  make_option(c("-c", "--cores"), type = "integer", default = 1,
              help = "Cores (currently runs sequentially) [default: %default]"),
  make_option(c("--phase1"), type = "integer", default = 200,
              help = "Random samples in phase 1 [default: %default]"),
  make_option(c("--phase2"), type = "integer", default = 200,
              help = "Random samples in phase 2 (refine) [default: %default]"),
  make_option(c("--lookback_min"), type = "integer", default = 2,
              help = "Min lookback bars [default: %default]"),
  make_option(c("--lookback_max"), type = "integer", default = 20,
              help = "Max lookback bars [default: %default]"),
  make_option(c("--drop_min"), type = "double", default = 2.0,
              help = "Min ATR drop threshold [default: %default]"),
  make_option(c("--drop_max"), type = "double", default = 12.0,
              help = "Max ATR drop threshold [default: %default]"),
  make_option(c("--tp_min"), type = "double", default = 0.2,
              help = "Min TP percent [default: %default]"),
  make_option(c("--tp_max"), type = "double", default = 8.0,
              help = "Max TP percent [default: %default]"),
  make_option(c("--sl_min"), type = "double", default = 0.2,
              help = "Min SL percent [default: %default]"),
  make_option(c("--sl_max"), type = "double", default = 12.0,
              help = "Max SL percent [default: %default]"),
  make_option(c("--atr_length"), type = "integer", default = 14,
              help = "ATR length for signalMode=\"atr\" [default: %default]"),
  make_option(c("--exit_mode"), type = "character", default = "close",
              help = "Exit mode: close or tradingview [default: %default]"),
  make_option(c("-s", "--seed"), type = "integer", default = 42,
              help = "Random seed [default: %default]"),
  make_option(c("-o", "--output_dir"), type = "character", default = "walkforward_atr",
              help = "Output directory [default: %default]")
)

opt <- parse_args(OptionParser(option_list = option_list))

dataset_name <- opt$dataset
update_binance_to <- trimws(opt$update_binance_to)
binance_sleep <- opt$binance_sleep
train_months <- opt$train_months
test_months <- opt$test_months
last_windows <- opt$last_windows
n_cores <- opt$cores
n_phase1 <- opt$phase1
n_phase2 <- opt$phase2
lookback_min <- opt$lookback_min
lookback_max <- opt$lookback_max
drop_min <- opt$drop_min
drop_max <- opt$drop_max
tp_min <- opt$tp_min
tp_max <- opt$tp_max
sl_min <- opt$sl_min
sl_max <- opt$sl_max
atr_length <- opt$atr_length
exit_mode <- match.arg(tolower(opt$exit_mode), c("close", "tradingview"))
seed <- opt$seed
output_dir <- opt$output_dir

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

cat("\n")
cat(sprintf("ATR Walk-Forward (quick) | dataset=%s | train=%dm | test=%dm | windows(last)=%d\n",
            dataset_name, train_months, test_months, last_windows))
cat(sprintf("Search: lookback[%d,%d], dropATR[%.2f,%.2f], TP%%[%.2f,%.2f], SL%%[%.2f,%.2f]\n",
            lookback_min, lookback_max, drop_min, drop_max, tp_min, tp_max, sl_min, sl_max))
cat(sprintf("Samples: phase1=%d, phase2=%d | cores=%d | atrLength=%d\n\n",
            n_phase1, n_phase2, n_cores, atr_length))

source("backtest_tradingview_aligned.R", encoding = "UTF-8")

interval_to_binance <- function(tf) tf

extract_symbol_tf <- function(dataset_name) {
  parts <- strsplit(dataset_name, "_", fixed = TRUE)[[1]]
  if (length(parts) < 2) stop("Invalid dataset name (expected SYMBOL_TF): ", dataset_name)
  list(symbol = parts[[1]], timeframe = parts[[2]])
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

cat("Loading data/liaochu.RData ...\n")
load("data/liaochu.RData")
stopifnot(exists("cryptodata"))

full_data <- cryptodata[[dataset_name]]
stopifnot(!is.null(full_data))

if (nzchar(update_binance_to)) {
  ds <- extract_symbol_tf(dataset_name)
  symbol <- ds$symbol
  interval <- interval_to_binance(ds$timeframe)

  date_str <- trimws(gsub("/", "-", update_binance_to, fixed = TRUE))
  end_day <- as.Date(date_str)
  if (is.na(end_day)) stop("Invalid --update_binance_to (expected date like 2026-01-01): ", update_binance_to)

  end_date <- as.POSIXct(sprintf("%s 23:59:59.999", format(end_day, "%Y-%m-%d")), tz = "UTC")
  last_ts <- max(index(full_data))

  if (is.finite(last_ts) && last_ts < end_date) {
    start_date <- as.POSIXct(last_ts, tz = "UTC") + 0.001
    cat(sprintf("\nDownloading %s %s klines from Binance: %s -> %s\n",
                symbol, interval,
                format(start_date, "%Y-%m-%d %H:%M:%OS3"),
                format(end_date, "%Y-%m-%d %H:%M:%OS3")))

    new_x <- download_binance_klines_xts(
      symbol = symbol,
      interval = interval,
      start_date = start_date,
      end_date = end_date,
      sleep_secs = binance_sleep
    )

    if (!is.null(new_x) && nrow(new_x) > 0) {
      before_n <- nrow(full_data)
      full_data <- rbind(full_data, new_x)
      full_data <- full_data[!duplicated(index(full_data))]
      full_data <- full_data[order(index(full_data))]
      cat(sprintf("OK appended %d rows (total %d -> %d)\n\n",
                  nrow(full_data) - before_n, before_n, nrow(full_data)))

      cache_file <- file.path(
        "data",
        sprintf("%s_binance_until_%s.RData", dataset_name, gsub("-", "", date_str, fixed = TRUE))
      )
      updated_dataset <- full_data
      save(updated_dataset, file = cache_file)
      cat(sprintf("Saved updated dataset cache: %s\n\n", cache_file))
    } else {
      cat("WARN no new data downloaded (skip update)\n\n")
    }
  } else {
    cat(sprintf("\nNo update needed: last=%s >= end=%s\n\n",
                as.character(last_ts), format(end_date, "%Y-%m-%d %H:%M:%OS3")))
  }
}

cat(sprintf("OK rows=%d | range=%s -> %s\n\n",
            nrow(full_data),
            as.character(index(full_data)[1]),
            as.character(index(full_data)[nrow(full_data)])))

split_data_by_month <- function(data) {
  dates <- index(data)
  year_month <- format(dates, "%Y-%m")
  unique_months <- unique(year_month)

  month_list <- list()
  for (ym in unique_months) {
    month_data <- data[year_month == ym]
    if (nrow(month_data) > 0) month_list[[ym]] <- month_data
  }
  month_list
}

generate_rolling_windows <- function(month_ids, train_size, test_size = 1) {
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

score_one <- function(result) {
  if (is.null(result) || is.null(result$TradeCount) || result$TradeCount <= 0) return(0)
  if (!is.finite(result$ReturnPercent)) return(0)
  if (!is.finite(result$MaxDrawdown)) return(0)
  if (!is.finite(result$WinRate)) return(0)

  # Hard filters to reduce overfitting on tiny samples
  if (result$TradeCount < 10) return(0)
  if (result$ReturnPercent <= 0) return(0)

  max_return <- 500  # cap for normalization (ATR mode tends to be noisier)
  max_trades <- 200
  normalized_return <- min(result$ReturnPercent / max_return, 1.0)
  normalized_winrate <- result$WinRate / 100
  normalized_drawdown_control <- 1 - abs(result$MaxDrawdown) / 100
  normalized_trades <- min(sqrt(result$TradeCount) / sqrt(max_trades), 1.0)

  w_return <- 0.45
  w_drawdown <- 0.30
  w_winrate <- 0.05
  w_trades <- 0.20

  w_return * normalized_return +
    w_drawdown * normalized_drawdown_control +
    w_winrate * normalized_winrate +
    w_trades * normalized_trades
}

eval_params <- function(params_df, data) {
  out <- vector("list", nrow(params_df))
  for (i in 1:nrow(params_df)) {
    p <- params_df[i, ]

    res <- tryCatch(
      backtest_tradingview_aligned(
        data = data,
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
        exitMode = exit_mode,
        signalMode = "atr",
        atrLength = atr_length
      ),
      error = function(e) NULL
    )

    score <- 0
    if (!is.null(res) &&
      is.finite(res$ReturnPercent) &&
      is.finite(res$MaxDrawdown) &&
      is.finite(res$WinRate) &&
      is.finite(res$TradeCount) &&
      res$TradeCount >= 10 &&
      res$ReturnPercent > 0) {
      max_return <- 500
      max_trades <- 200
      normalized_return <- min(res$ReturnPercent / max_return, 1.0)
      normalized_winrate <- res$WinRate / 100
      normalized_drawdown_control <- 1 - abs(res$MaxDrawdown) / 100
      normalized_trades <- min(sqrt(res$TradeCount) / sqrt(max_trades), 1.0)

      w_return <- 0.45
      w_drawdown <- 0.30
      w_winrate <- 0.05
      w_trades <- 0.20

      score <- w_return * normalized_return +
        w_drawdown * normalized_drawdown_control +
        w_winrate * normalized_winrate +
        w_trades * normalized_trades
    }

    out[[i]] <- data.table(
      lookback = p$lookback,
      minDrop = p$minDrop,
      TP = p$TP,
      SL = p$SL,
      score = score,
      return_pct = if (!is.null(res)) res$ReturnPercent else NA_real_,
      win_rate = if (!is.null(res)) res$WinRate else NA_real_,
      max_dd = if (!is.null(res)) res$MaxDrawdown else NA_real_,
      trades = if (!is.null(res)) res$TradeCount else NA_integer_,
      signals = if (!is.null(res)) res$SignalCount else NA_integer_
    )
  }
  rbindlist(out, fill = TRUE)
}

sample_params <- function(n) {
  data.frame(
    lookback = sample(lookback_min:lookback_max, n, replace = TRUE),
    minDrop = round(runif(n, drop_min, drop_max) * 20) / 20,
    TP = round(runif(n, tp_min, tp_max) * 20) / 20,
    SL = round(runif(n, sl_min, sl_max) * 20) / 20,
    stringsAsFactors = FALSE
  )
}

refine_params <- function(top_params, n) {
  out <- data.frame(lookback = integer(n), minDrop = numeric(n), TP = numeric(n), SL = numeric(n))
  for (i in 1:n) {
    base <- top_params[sample(nrow(top_params), 1), ]
    out$lookback[i] <- pmax(lookback_min, pmin(lookback_max, round(base$lookback + rnorm(1, 0, 2))))
    out$minDrop[i] <- round(pmax(drop_min, pmin(drop_max, base$minDrop + rnorm(1, 0, 1.5))) * 20) / 20
    out$TP[i] <- round(pmax(tp_min, pmin(tp_max, base$TP + rnorm(1, 0, 1.5))) * 20) / 20
    out$SL[i] <- round(pmax(sl_min, pmin(sl_max, base$SL + rnorm(1, 0, 2.0))) * 20) / 20
  }
  out
}

optimize_2stage <- function(train_data) {
  set.seed(seed)
  phase1_params <- sample_params(n_phase1)
  phase1_results <- eval_params(phase1_params, train_data)

  # Keep top 15% (or at least 10 candidates)
  phase1_results <- phase1_results[!is.na(phase1_results$score), ]
  phase1_results <- phase1_results[order(-phase1_results$score), ]

  keep_n <- max(10, as.integer(round(nrow(phase1_results) * 0.15)))
  top <- head(phase1_results, keep_n)
  top <- top[top$score > 0, ]
  if (nrow(top) < 3) {
    # fallback: still refine around best few (even if score==0)
    top <- head(phase1_results, min(10, nrow(phase1_results)))
  }

  phase2_params <- refine_params(top, n_phase2)
  phase2_results <- eval_params(phase2_params, train_data)

  final <- rbind(phase1_results, phase2_results)
  final <- final[!is.na(final$score), ]
  final <- final[order(-final$score), ]

  best <- final[1, ]
  list(best = best, all = final)
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

# NOTE: Runs sequentially for reliability on Windows (no PSOCK cluster).

month_list <- split_data_by_month(full_data)
month_ids <- names(month_list)
stopifnot(length(month_ids) >= (train_months + test_months + 1))

windows <- generate_rolling_windows(month_ids, train_months, test_size = test_months)
if (!is.null(last_windows) && is.finite(last_windows) && last_windows > 0) {
  windows <- tail(windows, last_windows)
}

cat(sprintf("Running %d windows...\n\n", length(windows)))

all_rows <- list()
for (w in windows) {
  train_month_ids <- w$train_months
  test_month_ids <- w$test_months

  train_data <- do.call(rbind, lapply(train_month_ids, function(m) month_list[[m]]))
  test_data <- do.call(rbind, lapply(test_month_ids, function(m) month_list[[m]]))

  cat(sprintf("[Window %d] train=%s | test=%s | trainRows=%d | testRows=%d\n",
              w$window_id,
              paste(train_month_ids, collapse = ","),
              paste(test_month_ids, collapse = ","),
              nrow(train_data),
              nrow(test_data)))

  opt_start <- Sys.time()
  opt_res <- optimize_2stage(train_data)
  opt_secs <- as.numeric(difftime(Sys.time(), opt_start, units = "secs"))

  best <- opt_res$best
  cat(sprintf("  best: lookback=%d dropATR=%.2f TP=%.2f%% SL=%.2f%% | trainRet=%.2f%% trades=%d | opt=%.1fs\n",
              best$lookback, best$minDrop, best$TP, best$SL, best$return_pct, best$trades, opt_secs))

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
    exitMode = exit_mode,
    signalMode = "atr",
    atrLength = atr_length
  )

  all_rows[[length(all_rows) + 1]] <- data.frame(
    window_id = w$window_id,
    train_months = paste(train_month_ids, collapse = "|"),
    test_months = paste(test_month_ids, collapse = "|"),
    lookback = best$lookback,
    minDrop = best$minDrop,
    TP = best$TP,
    SL = best$SL,
    atrLength = atr_length,
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
    opt_time_secs = opt_secs,
    stringsAsFactors = FALSE
  )

  cat(sprintf("  test:  ret=%.2f%% win=%.1f%% maxDD=%.1f%% trades=%d signals=%d\n\n",
              test_bt$ReturnPercent, test_bt$WinRate, test_bt$MaxDrawdown, test_bt$TradeCount, test_bt$SignalCount))
}

results_df <- rbindlist(all_rows, fill = TRUE)
setorder(results_df, window_id)

monthly_returns <- results_df$test_return_pct
equity <- calc_equity_curve(monthly_returns, initial_capital = 10000)
cum_return_pct <- (tail(equity, 1) / 10000 - 1) * 100
max_dd_total <- calc_max_drawdown(equity)

mean_m <- mean(monthly_returns, na.rm = TRUE)
sd_m <- sd(monthly_returns, na.rm = TRUE)
sharpe <- if (is.finite(sd_m) && sd_m > 0) (mean_m / sd_m) * sqrt(12) else NA_real_

positive_months <- sum(monthly_returns > 0, na.rm = TRUE)
negative_months <- sum(monthly_returns < 0, na.rm = TRUE)
zero_months <- sum(monthly_returns == 0, na.rm = TRUE)

param_stats <- list(
  lookback_mean = mean(results_df$lookback, na.rm = TRUE),
  lookback_sd = sd(results_df$lookback, na.rm = TRUE),
  minDrop_mean = mean(results_df$minDrop, na.rm = TRUE),
  minDrop_sd = sd(results_df$minDrop, na.rm = TRUE),
  TP_mean = mean(results_df$TP, na.rm = TRUE),
  TP_sd = sd(results_df$TP, na.rm = TRUE),
  SL_mean = mean(results_df$SL, na.rm = TRUE),
  SL_sd = sd(results_df$SL, na.rm = TRUE)
)

detail_file <- file.path(output_dir, sprintf("%s_atr_wf_details.csv", dataset_name))
fwrite(results_df, detail_file)

summary_file <- file.path(output_dir, sprintf("%s_atr_wf_summary.md", dataset_name))
summary_md <- c(
  sprintf("# ATR Walk-Forward Summary — %s", dataset_name),
  "",
  sprintf("- signalMode: `atr` (atrLength=%d)", atr_length),
  sprintf("- exitMode: `%s`", exit_mode),
  sprintf("- windows: %d (train=%d months, test=%d months, last_windows=%d)",
          nrow(results_df), train_months, test_months, last_windows),
  sprintf("- cumulative out-of-sample return: %.2f%%", cum_return_pct),
  sprintf("- max drawdown (OS equity curve): %.2f%%", max_dd_total),
  sprintf("- avg monthly return: %.2f%% (sd %.2f%%), Sharpe~%.2f", mean_m, sd_m, sharpe),
  sprintf("- OS months: +%d / -%d / 0=%d", positive_months, negative_months, zero_months),
  "",
  "## Parameter stability",
  "",
  sprintf("- lookback: mean=%.2f sd=%.2f", param_stats$lookback_mean, param_stats$lookback_sd),
  sprintf("- dropATR:  mean=%.2f sd=%.2f", param_stats$minDrop_mean, param_stats$minDrop_sd),
  sprintf("- TP%%:     mean=%.2f sd=%.2f", param_stats$TP_mean, param_stats$TP_sd),
  sprintf("- SL%%:     mean=%.2f sd=%.2f", param_stats$SL_mean, param_stats$SL_sd),
  "",
  sprintf("Details CSV: `%s`", detail_file)
)
writeLines(summary_md, summary_file, useBytes = TRUE)

cat("DONE\n")
cat(sprintf("Details: %s\n", detail_file))
cat(sprintf("Summary: %s\n", summary_file))

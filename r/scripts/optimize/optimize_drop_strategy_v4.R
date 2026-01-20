suppressMessages({
  library(xts); library(data.table); library(pbapply); library(TTR)
})

DATA_PATH <- "data/liaochu.RData"
INIT_EQUITY <- 100000
FEE <- 0.001
NEXT_BAR_ENTRY <- FALSE
SMOKE_SYMBOLS <- 2
CLUSTER_CORES <- 32

tp_seq <- seq(5, 25, by = 1)
param_grid <- expand.grid(
  lookbackDays = 2:7,
  minDropPercent = seq(5, 20, by = 1),
  takeProfitPercent = tp_seq,
  stopLossPercent = tp_seq
)

infer_tf_minutes <- function(name) {
  tf <- sub(".*_(.*)$", "\\1", name)
  if (grepl("m$", tf)) return(as.integer(sub("m$", "", tf)))
  if (grepl("h$", tf)) return(as.integer(sub("h$", "", tf)) * 60)
  if (grepl("d$", tf)) return(as.integer(sub("d$", "", tf)) * 24 * 60)
  stop("Unknown TF: ", tf)
}

build_signals <- function(dat, tf_minutes, lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent, next_bar_entry = TRUE) {
  H <- dat$High; L <- dat$Low; O <- dat$Open; C <- dat$Close
  n <- NROW(dat)
  if (n < 10) return(list(buy = integer(0), sell = integer(0), open = O, close = C))
  # Pine 中 length 语义为“bar数”，不转天数
  lookbackBars <- max(2L, as.integer(lookbackDays))
  hh <- xts::xts(TTR::runMax(as.numeric(H), n = lookbackBars), order.by = index(H))
  hh_prev <- lag.xts(hh, 1)
  percentDrop <- (as.numeric(hh_prev) - as.numeric(L)) / as.numeric(hh_prev) * 100
  cond_priceDrop <- !is.na(percentDrop) & (percentDrop >= minDropPercent)

  buy_signal <- integer(n); sell_signal <- integer(n)
  in_trade <- FALSE; entry_price <- NA_real_

  for (i in seq_len(n)) {
    if (!in_trade && isTRUE(cond_priceDrop[i])) {
      in_trade <- TRUE
      entry_price <- if (next_bar_entry && i < n) as.numeric(O[i+1]) else as.numeric(C[i])
      buy_signal[i] <- 1
    } else if (in_trade) {
      tp_price <- entry_price * (1 + takeProfitPercent/100)
      sl_price <- entry_price * (1 - stopLossPercent/100)
      price_chk <- as.numeric(C[i])
      if (!is.na(price_chk) && (price_chk >= tp_price || price_chk <= sl_price)) {
        sell_signal[i] <- 1
        in_trade <- FALSE; entry_price <- NA_real_
      }
    }
  }
  list(buy = buy_signal, sell = sell_signal, open = O, close = C)
}

simulate_nav <- function(O, C, buy, sell, init_equity = 100000, fee = 0.001, next_bar_entry = TRUE) {
  n <- length(C)
  if (n == 0L) return(list(nav = numeric(0), returns = numeric(0)))
  nav <- numeric(n); nav[1] <- init_equity
  in_trade <- FALSE; entry_idx <- NA_integer_; entry_price <- NA_real_; nav_entry <- NA_real_

  for (t in 2:n) {
    nav[t] <- nav[t-1]
    if (!in_trade && t <= length(buy) && buy[t] == 1L) {
      entry_idx <- if (next_bar_entry && t < n) t + 1L else t
      entry_price <- if (next_bar_entry && t < n) as.numeric(O[entry_idx]) else as.numeric(C[t])
      if (entry_idx <= n) {
        nav[entry_idx] <- nav[entry_idx] * (1 - fee)
        nav_entry <- nav[entry_idx]
        in_trade <- TRUE
      }
    }
    if (in_trade && !is.na(entry_idx) && t >= entry_idx) {
      nav[t] <- nav_entry * (as.numeric(C[t]) / entry_price)
      if (t <= length(sell) && sell[t] == 1L) {
        nav[t] <- nav[t] * (1 - fee)
        in_trade <- FALSE; entry_idx <- NA_integer_; entry_price <- NA_real_; nav_entry <- NA_real_
      }
    }
  }
  if (in_trade && !is.na(entry_idx)) {
    nav[n] <- nav_entry * (as.numeric(C[n]) / entry_price) * (1 - fee)
  }
  returns <- c(0, diff(nav))
  list(nav = nav, returns = returns)
}

max_drawdown <- function(nav) {
  if (length(nav) == 0) return(NA_real_)
  peak <- cummax(nav)
  draw <- nav/peak - 1
  abs(min(draw, na.rm = TRUE))
}

trade_stats <- function(O, C, buy, sell, fee = 0.001, next_bar_entry = TRUE) {
  n <- length(C)
  trades <- list()
  in_trade <- FALSE; entry_price <- NA_real_
  for (i in seq_len(n)) {
    if (!in_trade && i <= length(buy) && buy[i] == 1L) {
      entry_price <- if (next_bar_entry && i < n) as.numeric(O[i+1]) else as.numeric(C[i])
      in_trade <- TRUE
    } else if (in_trade && i <= length(sell) && sell[i] == 1L) {
      exit_price <- as.numeric(C[i])
      gross_ret <- (exit_price - entry_price) / entry_price
      net_factor <- (1 - fee) * (1 - fee) * (1 + gross_ret)
      trades[[length(trades) + 1L]] <- list(gross_ret = gross_ret, net_factor = net_factor)
      in_trade <- FALSE; entry_price <- NA_real_
    }
  }
  if (length(trades) == 0L) return(list(count = 0L, win_rate = NA_real_))
  gross <- sapply(trades, `[[`, "gross_ret")
  win_rate <- sum(gross > 0) / sum(gross != 0)
  list(count = length(trades), win_rate = win_rate)
}

safe_row <- function(dat, name, p, init_equity, fee, next_bar_entry) {
  tryCatch({
    sig <- build_signals(dat, infer_tf_minutes(name),
                         lookbackDays = p$lookbackDays,
                         minDropPercent = p$minDropPercent,
                         takeProfitPercent = p$takeProfitPercent,
                         stopLossPercent = p$stopLossPercent,
                         next_bar_entry = next_bar_entry)
    sim <- simulate_nav(sig$open, sig$close, sig$buy, sig$sell, init_equity, fee, next_bar_entry)
    final_capital <- if (length(sim$nav)) tail(sim$nav, 1) else NA_real_
    ret_pct <- if (!is.na(final_capital)) (final_capital / init_equity - 1) * 100 else NA_real_
    mdd <- max_drawdown(sim$nav)
    ts <- trade_stats(sig$open, sig$close, sig$buy, sig$sell, fee, next_bar_entry)
    bh <- if (length(sig$open)) as.numeric(tail(sig$open, 1) / head(sig$open, 1) - 1) else NA_real_
    excess <- if (!is.na(ret_pct) && !is.na(bh)) ret_pct/100 - bh else NA_real_
    data.frame(
      symbol = name,
      lookbackDays = p$lookbackDays,
      minDropPercent = p$minDropPercent,
      takeProfitPercent = p$takeProfitPercent,
      stopLossPercent = p$stopLossPercent,
      Final_Capital = final_capital,
      Return_Percentage = ret_pct,
      Trade_Count = ts$count,
      Max_Drawdown = mdd,
      Win_Rate = ts$win_rate,
      BH_Return = bh,
      Excess_Return = excess
    )
  }, error = function(e) {
    data.frame(
      symbol = name,
      lookbackDays = p$lookbackDays,
      minDropPercent = p$minDropPercent,
      takeProfitPercent = p$takeProfitPercent,
      stopLossPercent = p$stopLossPercent,
      Final_Capital = NA_real_,
      Return_Percentage = NA_real_,
      Trade_Count = 0L,
      Max_Drawdown = NA_real_,
      Win_Rate = NA_real_,
      BH_Return = NA_real_,
      Excess_Return = NA_real_
    )
  })
}

optimize_one_symbol <- function(dat, name, grid, init_equity, fee, next_bar_entry) {
  pboptions(type = "timer", char = "=", style = 1)
  res <- pblapply(split(grid, seq(nrow(grid))), function(p) safe_row(dat, name, p, init_equity, fee, next_bar_entry))
  data.table::rbindlist(res)[order(-Return_Percentage, Max_Drawdown)]
}

load(DATA_PATH)
stopifnot(exists("cryptodata"), is.list(cryptodata))
symbols <- names(cryptodata)

# ---------- Smoke Test with parallel & progress ----------
pboptions(type = "txt", char = "=", style = 3)
smoke_syms <- head(symbols, SMOKE_SYMBOLS)
message("[Smoke] symbols: ", paste(smoke_syms, collapse = ", "))
cl_smoke <- parallel::makeCluster(min(CLUSTER_CORES, length(smoke_syms)))
parallel::clusterEvalQ(cl_smoke, { suppressMessages(library(xts)); suppressMessages(library(data.table)); suppressMessages(library(pbapply)); suppressMessages(library(TTR)); })
parallel::clusterExport(cl_smoke, varlist = c(
  "cryptodata", "param_grid", "INIT_EQUITY", "FEE", "NEXT_BAR_ENTRY",
  "infer_tf_minutes", "build_signals", "simulate_nav", "max_drawdown", "trade_stats", "safe_row", "optimize_one_symbol"
), envir = environment())
smoke_results <- pblapply(smoke_syms, function(nm) {
  optimize_one_symbol(
    dat = cryptodata[[nm]], name = nm, grid = param_grid,
    init_equity = INIT_EQUITY, fee = FEE, next_bar_entry = NEXT_BAR_ENTRY
  )
}, cl = cl_smoke)
parallel::stopCluster(cl_smoke)
smoke_dt <- data.table::rbindlist(smoke_results)
write.csv(smoke_dt, file = "smoke_results.csv", row.names = FALSE)
message("[Smoke] saved: smoke_results.csv (rows=", nrow(smoke_dt), ")")

# ---------- Full Parallel Run with per-symbol progress ----------
pboptions(type = "txt", char = "=", style = 3)
message("[Full] starting parallel run with ", CLUSTER_CORES, " cores...")
cl <- parallel::makeCluster(CLUSTER_CORES)
parallel::clusterEvalQ(cl, { suppressMessages(library(xts)); suppressMessages(library(data.table)); suppressMessages(library(pbapply)); suppressMessages(library(TTR)); })
parallel::clusterExport(cl, varlist = c(
  "cryptodata", "symbols", "param_grid", "INIT_EQUITY", "FEE", "NEXT_BAR_ENTRY",
  "infer_tf_minutes", "build_signals", "simulate_nav", "max_drawdown", "trade_stats", "safe_row", "optimize_one_symbol"
), envir = environment())
full_results_list <- pblapply(symbols, function(nm) {
  optimize_one_symbol(
    dat = cryptodata[[nm]], name = nm, grid = param_grid,
    init_equity = INIT_EQUITY, fee = FEE, next_bar_entry = NEXT_BAR_ENTRY
  )
}, cl = cl)
parallel::stopCluster(cl)
full_dt <- data.table::rbindlist(full_results_list)
write.csv(full_dt, file = "drop_strategy_results.csv", row.names = FALSE)
message("[Full] saved: drop_strategy_results.csv (rows=", nrow(full_dt), ")")

best_by_symbol <- full_dt[, .SD[order(-Return_Percentage, Max_Drawdown)][1], by = symbol]
write.csv(best_by_symbol, file = "drop_strategy_best_by_symbol.csv", row.names = FALSE)
message("[Full] saved: drop_strategy_best_by_symbol.csv (rows=", nrow(best_by_symbol), ")")
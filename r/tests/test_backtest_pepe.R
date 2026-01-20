library(xts)
load("data/liaochu.RData")

symbol <- "PEPEUSDT_15m"
data <- cryptodata[[symbol]]

build_signals <- function(data, lookbackDays, minDropPercent) {
  if (nrow(data) < lookbackDays + 1) return(rep(FALSE, nrow(data)))
  lookbackBars <- lookbackDays
  signals <- rep(FALSE, nrow(data))
  for (i in (lookbackBars + 1):nrow(data)) {
    window_start <- max(1, i - lookbackBars)
    window_data <- data[window_start:(i-1), ]
    if (nrow(window_data) == 0) next
    window_high <- max(window_data$High, na.rm = TRUE)
    current_low <- data$Low[i]
    if (!is.na(window_high) && !is.na(current_low)) {
      drop_percent <- ((window_high - current_low) / window_high) * 100
      if (drop_percent >= minDropPercent) signals[i] <- TRUE
    }
  }
  signals
}

backtest_strategy <- function(data, lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent, next_bar_entry=FALSE) {
  signals <- build_signals(data, lookbackDays, minDropPercent)
  cat("信号数量:", sum(signals, na.rm=TRUE), "\n")
  capital <- 10000
  position <- 0
  entry_price <- NA_real_
  trades <- numeric(0)
  enter_count <- 0
  exit_count <- 0
  for (i in 1:nrow(data)) {
    if (signals[i] && position == 0) {
      entry_price <- if (next_bar_entry && i < nrow(data)) data$Open[i+1] else data$Close[i]
      position <- capital / entry_price
      capital <- 0
      enter_count <- enter_count + 1
    }
    if (position > 0) {
      current_price <- data$Close[i]
      pnl_percent <- ((current_price - entry_price) / entry_price) * 100
      if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
        exit_capital <- position * current_price
        trades <- c(trades, pnl_percent)
        capital <- exit_capital
        position <- 0
        exit_count <- exit_count + 1
      }
    }
  }
  if (position > 0) {
    final_pnl <- ((data$Close[nrow(data)] - entry_price) / entry_price) * 100
    trades <- c(trades, final_pnl)
    capital <- position * data$Close[nrow(data)]
    exit_count <- exit_count + 1
  }
  cat("进入次数:", enter_count, " 退出次数:", exit_count, " 交易数:", length(trades), "\n")
  list(trade_count=length(trades), final_capital=capital, return_pct=((capital-10000)/10000)*100)
}

res <- backtest_strategy(data, lookbackDays=3, minDropPercent=5, takeProfitPercent=6, stopLossPercent=6, next_bar_entry=FALSE)
print(res)

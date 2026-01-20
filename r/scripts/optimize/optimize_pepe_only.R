# PEPEUSDT单标优化脚本 - 改进进度条版本
# 每完成一个参数组合就更新进度显示

# 加载必要的包
library(pbapply)
library(parallel)

# 配置参数
CLUSTER_CORES <- 32
NEXT_BAR_ENTRY <- FALSE  # 收盘价入场，对齐Pine Script

# 参数网格（用户修改后的版本）
tp_seq <- seq(5, 20, by = 1)
param_grid <- expand.grid(
  lookbackDays = 3:7,
  minDropPercent = seq(5, 20, by = 1),
  takeProfitPercent = tp_seq,
  stopLossPercent = tp_seq
)

cat("参数组合总数:", nrow(param_grid), "\n")

# 加载数据
load("data/liaochu.RData")

# 筛选PEPEUSDT相关标的
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("PEPEUSDT分时框架:", paste(pepe_symbols, collapse=", "), "\n")
cat("分时框架数量:", length(pepe_symbols), "\n")

# 策略函数
build_signals <- function(data, lookbackDays, minDropPercent) {
  if (nrow(data) < lookbackDays + 1) return(rep(FALSE, nrow(data)))
  
  lookbackBars <- lookbackDays  # 直接使用bar数，不转换
  signals <- rep(FALSE, nrow(data))
  
  for (i in (lookbackBars + 1):nrow(data)) {
    window_start <- max(1, i - lookbackBars)
    window_data <- data[window_start:(i-1), ]
    
    if (nrow(window_data) == 0) next
    
    window_high <- max(as.numeric(window_data[, "High"]), na.rm = TRUE)
    current_low <- as.numeric(data[i, "Low"])
    
    if (!is.na(window_high) && !is.na(current_low)) {
      drop_percent <- ((window_high - current_low) / window_high) * 100
      if (drop_percent >= minDropPercent) {
        signals[i] <- TRUE
      }
    }
  }
  
  return(signals)
}

backtest_strategy <- function(data, lookbackDays, minDropPercent, takeProfitPercent, stopLossPercent) {
  tryCatch({
    if (nrow(data) < 10) return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, BH_Return = NA, Excess_Return = NA
    ))
    
    signals <- build_signals(data, lookbackDays, minDropPercent)
    
    if (sum(signals, na.rm = TRUE) == 0) return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, BH_Return = NA, Excess_Return = NA
    ))
    
    capital <- 10000
    position <- 0
    entry_price <- 0
    trades <- c()
    capital_curve <- c()
    
    for (i in 1:nrow(data)) {
      if (signals[i] && position == 0) {
        entry_price <- if (NEXT_BAR_ENTRY && i < nrow(data)) as.numeric(data[i+1, "Open"]) else as.numeric(data[i, "Close"])
        if (!is.na(entry_price) && entry_price > 0) {
          position <- capital / entry_price
          capital <- 0
        }
      }
      
      if (position > 0) {
        current_price <- data$Close[i]
        if (!is.na(current_price) && current_price > 0 && entry_price > 0) {
          pnl_percent <- ((current_price - entry_price) / entry_price) * 100
          
          if (pnl_percent >= takeProfitPercent || pnl_percent <= -stopLossPercent) {
            exit_capital <- position * current_price
            trades <- c(trades, pnl_percent)
            capital <- exit_capital
            position <- 0
            entry_price <- 0
          }
        }
      }
      
      portfolio_value <- if (position > 0 && !is.na(data$Close[i]) && data$Close[i] > 0) {
        position * as.numeric(data[i, "Close"])
      } else {
        capital
      }
      capital_curve <- c(capital_curve, portfolio_value)
    }
    
    if (position > 0 && !is.na(data$Close[nrow(data)]) && data$Close[nrow(data)] > 0) {
      final_pnl <- ((as.numeric(data[nrow(data), "Close"]) - entry_price) / entry_price) * 100
      trades <- c(trades, final_pnl)
      capital <- position * as.numeric(data[nrow(data), "Close"]) 
    }
    
    if (length(trades) == 0) return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, BH_Return = NA, Excess_Return = NA
    ))
    
    final_capital <- capital
    return_pct <- ((final_capital - 10000) / 10000) * 100
    
    if (length(capital_curve) > 0) {
      peak <- cummax(capital_curve)
      drawdown <- (capital_curve - peak) / peak * 100
      max_drawdown <- min(drawdown, na.rm = TRUE)
    } else {
      max_drawdown <- 0
    }
    
    win_rate <- sum(trades > 0) / length(trades) * 100
    
    bh_return <- ((as.numeric(data[nrow(data), "Close"]) - as.numeric(data[1, "Close"])) / as.numeric(data[1, "Close"])) * 100
    excess_return <- return_pct - bh_return
    
    return(list(
      Final_Capital = final_capital,
      Return_Percentage = return_pct,
      Max_Drawdown = max_drawdown,
      Win_Rate = win_rate,
      Trade_Count = length(trades),
      BH_Return = bh_return,
      Excess_Return = excess_return
    ))
  }, error = function(e) {
    return(list(
      Final_Capital = NA, Return_Percentage = NA, Max_Drawdown = NA,
      Win_Rate = NA, Trade_Count = 0, BH_Return = NA, Excess_Return = NA
    ))
  })
}

# 单个参数组合测试函数（带进度更新）
test_single_combination <- function(i, param_grid, symbols_data, progress_env) {
  params <- param_grid[i, ]
  
  results <- list()
  for (symbol in names(symbols_data)) {
    data <- symbols_data[[symbol]]
    result <- backtest_strategy(data, params$lookbackDays, params$minDropPercent, 
                               params$takeProfitPercent, params$stopLossPercent)
    
    sig_vec <- build_signals(data, params$lookbackDays, params$minDropPercent)
    sig_count <- if (length(sig_vec) > 0) sum(sig_vec, na.rm = TRUE) else 0L
    
    results[[length(results) + 1]] <- data.frame(
      Symbol = symbol,
      lookbackDays = as.numeric(params$lookbackDays),
      minDropPercent = as.numeric(params$minDropPercent),
      takeProfitPercent = as.numeric(params$takeProfitPercent),
      stopLossPercent = as.numeric(params$stopLossPercent),
      Signal_Count = as.integer(sig_count),
      Final_Capital = as.numeric(result$Final_Capital),
      Return_Percentage = as.numeric(result$Return_Percentage),
      Trade_Count = as.integer(result$Trade_Count),
      Max_Drawdown = as.numeric(result$Max_Drawdown),
      Win_Rate = as.numeric(result$Win_Rate),
      BH_Return = as.numeric(result$BH_Return),
      Excess_Return = as.numeric(result$Excess_Return),
      stringsAsFactors = FALSE
    )
  }
  
  # 更新进度
  progress_env$completed <- progress_env$completed + 1
  cat(sprintf("\r进度: %d/%d (%.1f%%) - 参数组合 %d 完成", 
              progress_env$completed, progress_env$total, 
              (progress_env$completed / progress_env$total) * 100, i))
  flush.console()
  
  return(do.call(rbind, results))
}

# 准备PEPEUSDT数据
pepe_data <- cryptodata[pepe_symbols]
names(pepe_data) <- pepe_symbols

cat("\n开始PEPEUSDT优化...\n")
cat("使用", CLUSTER_CORES, "个CPU核心\n")
cat("参数组合总数:", nrow(param_grid), "\n")
cat("分时框架数:", length(pepe_symbols), "\n")
cat("总计算任务数:", nrow(param_grid), "个参数组合\n\n")

# 创建进度环境
progress_env <- new.env()
progress_env$completed <- 0
progress_env$total <- nrow(param_grid)

# 开始并行计算
start_time <- Sys.time()

# 创建集群
cl <- makeCluster(CLUSTER_CORES)
clusterEvalQ(cl, {
  library(pbapply)
})

# 导出必要的变量和函数到集群
clusterExport(cl, c("build_signals", "backtest_strategy", "test_single_combination", 
                   "pepe_data", "param_grid", "NEXT_BAR_ENTRY", "progress_env"))

# 执行并行计算
cat("开始并行计算...\n")
results_list <- parLapply(cl, 1:nrow(param_grid), function(i) {
  test_single_combination(i, param_grid, pepe_data, progress_env)
})

# 停止集群
stopCluster(cl)

cat("\n\n计算完成！\n")

# 合并结果
all_results <- do.call(rbind, results_list)

# 保存结果
output_file <- "pepe_results.csv"
write.csv(all_results, output_file, row.names = FALSE)

end_time <- Sys.time()
elapsed_time <- end_time - start_time

cat("结果已保存到:", output_file, "\n")
cat("总行数:", nrow(all_results), "\n")
cat("计算耗时:", round(as.numeric(elapsed_time, units = "mins"), 2), "分钟\n")

# 快速统计
valid_results <- all_results[!is.na(all_results$Return_Percentage), ]
cat("有效结果数:", nrow(valid_results), "\n")
if (nrow(valid_results) > 0) {
  cat("最佳收益率:", round(max(valid_results$Return_Percentage, na.rm = TRUE), 2), "%\n")
  cat("平均交易次数:", round(mean(valid_results$Trade_Count, na.rm = TRUE), 1), "\n")
}

cat("\n优化完成！请查看", output_file, "文件获取详细结果。\n")

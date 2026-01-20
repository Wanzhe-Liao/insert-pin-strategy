# 调试PEPEUSDT数据和信号生成
library(xts)
load("data/liaochu.RData")

cat("=== PEPEUSDT数据调试 ===\n")

# 检查数据对象
cat("数据对象名称:", ls(), "\n")

# 检查PEPEUSDT符号
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat("PEPEUSDT符号:", paste(pepe_symbols, collapse=", "), "\n")

# 检查第一个PEPEUSDT数据
if(length(pepe_symbols) > 0) {
  symbol <- pepe_symbols[1]
  data <- cryptodata[[symbol]]
  cat("\n=== ", symbol, " 数据检查 ===\n")
  cat("数据行数:", nrow(data), "\n")
  cat("列名:", paste(colnames(data), collapse=", "), "\n")
  
  if(nrow(data) > 0) {
    idxs <- index(data)
    cat("时间范围:", as.character(idxs[1]), "到", as.character(idxs[nrow(data)]), "\n")
    cat("价格统计:\n")
    cat("  开盘价范围:", min(data$Open, na.rm=TRUE), "-", max(data$Open, na.rm=TRUE), "\n")
    cat("  最高价范围:", min(data$High, na.rm=TRUE), "-", max(data$High, na.rm=TRUE), "\n")
    cat("  最低价范围:", min(data$Low, na.rm=TRUE), "-", max(data$Low, na.rm=TRUE), "\n")
    cat("  收盘价范围:", min(data$Close, na.rm=TRUE), "-", max(data$Close, na.rm=TRUE), "\n")
    
    # 测试插针信号生成
    cat("\n=== 测试插针信号生成 ===\n")
    
    # 简化的插针检测函数
    test_drop_signal <- function(data, lookbackDays = 3, minDropPercent = 5) {
      n <- nrow(data)
      signals <- rep(FALSE, n)
      
      if(n < lookbackDays + 1) return(signals)
      
      for(i in (lookbackDays + 1):n) {
        # 获取回看窗口的最高价
        window_high <- max(data$High[(i-lookbackDays):(i-1)], na.rm=TRUE)
        current_low <- data$Low[i]
        
        # 计算跌幅
        drop_percent <- (window_high - current_low) / window_high * 100
        
        if(drop_percent >= minDropPercent) {
          signals[i] <- TRUE
        }
      }
      
      return(signals)
    }
    
    # 测试不同参数
    test_params <- list(
      list(lookback=1, drop=5),
      list(lookback=3, drop=5),
      list(lookback=5, drop=3),
      list(lookback=3, drop=10)
    )
    
    for(params in test_params) {
      signals <- test_drop_signal(data, params$lookback, params$drop)
      signal_count <- sum(signals)
      cat(sprintf("参数 lookback=%d, drop=%.1f%%: 信号数量=%d\n", 
                  params$lookback, params$drop, signal_count))
      
      if(signal_count > 0) {
        signal_indices <- which(signals)
        cat("  前5个信号位置:", paste(head(signal_indices, 5), collapse=", "), "\n")
        
        # 显示第一个信号的详细信息
        idx <- signal_indices[1]
        window_start <- max(1, idx - params$lookback)
        window_high <- max(data$High[window_start:(idx-1)], na.rm=TRUE)
        current_low <- data$Low[idx]
        drop_percent <- (window_high - current_low) / window_high * 100
        
        cat(sprintf("  第一个信号详情: 时间=%s, 窗口最高=%.6f, 当前最低=%.6f, 跌幅=%.2f%%\n",
                    as.character(index(data)[idx]), window_high, current_low, drop_percent))
      }
    }
  }
}

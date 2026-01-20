# ============================================================================
# PEPEUSDT 超级优化版 - 完整执行脚本
# ============================================================================
# 创建日期: 2025-10-26
# 目标: 在15-20分钟内完成81,920次回测（32核并行）
#
# 主要特性:
# - 向量化信号生成（10-20x加速）
# - 优化的并行策略（按时间框架分组）
# - 自动检查点保存
# - 实时进度监控
# - 内存优化
#
# 预期性能: 5-10倍加速
# ============================================================================

# 加载必要的包
suppressMessages({
  library(parallel)
  library(xts)
  library(RcppRoll)
})

# ============================================================================
# 配置参数
# ============================================================================

CLUSTER_CORES <- 32
NEXT_BAR_ENTRY <- FALSE  # 对齐Pine Script
ENABLE_CHECKPOINTS <- TRUE  # 启用检查点
CHECKPOINT_INTERVAL <- 5000  # 每5000个任务保存一次

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("PEPEUSDT 超级优化版参数扫描\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

cat(sprintf("CPU核心数: %d\n", CLUSTER_CORES))
cat(sprintf("检查点: %s (间隔: %d任务)\n",
            ifelse(ENABLE_CHECKPOINTS, "启用", "禁用"),
            CHECKPOINT_INTERVAL))

# ============================================================================
# 参数网格
# ============================================================================

tp_seq <- seq(5, 20, by = 1)
param_grid <- expand.grid(
  lookbackDays = 3:7,
  minDropPercent = seq(5, 20, by = 1),
  takeProfitPercent = tp_seq,
  stopLossPercent = tp_seq,
  stringsAsFactors = FALSE
)

cat(sprintf("\n参数组合总数: %s\n", format(nrow(param_grid), big.mark = ",")))
cat(sprintf("  lookbackDays: 3-7 (%d值)\n", length(3:7)))
cat(sprintf("  minDropPercent: 5-20%% (%d值)\n", length(seq(5, 20, 1))))
cat(sprintf("  TP/SL: 5-20%% (%d值)\n", length(tp_seq)))

# ============================================================================
# 加载数据和优化函数
# ============================================================================

cat("\n加载数据...\n")
load("data/liaochu.RData")

# 加载优化函数库
source("backtest_optimized.R")

# 获取PEPEUSDT数据
pepe_symbols <- names(cryptodata)[grepl("PEPEUSDT", names(cryptodata))]
cat(sprintf("找到 %d 个PEPEUSDT时间框架:\n", length(pepe_symbols)))
for (sym in pepe_symbols) {
  cat(sprintf("  - %s (%s 行)\n", sym, format(nrow(cryptodata[[sym]]), big.mark = ",")))
}

total_tasks <- nrow(param_grid) * length(pepe_symbols)
cat(sprintf("\n总任务数: %s\n", format(total_tasks, big.mark = ",")))

# ============================================================================
# 检查点管理
# ============================================================================

save_checkpoint <- function(results, checkpoint_name, metadata = NULL) {
  if (!ENABLE_CHECKPOINTS) return(invisible(NULL))

  checkpoint_file <- sprintf("checkpoint_%s.rds", checkpoint_name)
  checkpoint_data <- list(
    results = results,
    timestamp = Sys.time(),
    metadata = metadata
  )

  saveRDS(checkpoint_data, checkpoint_file)
  cat(sprintf("  [检查点] 已保存: %s (%.1f MB)\n",
              checkpoint_file,
              file.size(checkpoint_file) / 1024^2))
  invisible(checkpoint_file)
}

load_checkpoint <- function(checkpoint_name) {
  checkpoint_file <- sprintf("checkpoint_%s.rds", checkpoint_name)

  if (file.exists(checkpoint_file)) {
    cat(sprintf("发现检查点: %s\n", checkpoint_file))
    cat("正在恢复...\n")

    checkpoint_data <- readRDS(checkpoint_file)
    cat(sprintf("  恢复时间: %s\n", checkpoint_data$timestamp))
    cat(sprintf("  已完成: %d 个任务\n", nrow(checkpoint_data$results)))

    return(checkpoint_data)
  }

  return(NULL)
}

# ============================================================================
# 单个参数组合测试函数（优化版）
# ============================================================================

test_single_param <- function(param_row, data, symbol_name) {
  # 执行优化版回测
  result <- backtest_strategy_optimized(
    data,
    param_row$lookbackDays,
    param_row$minDropPercent,
    param_row$takeProfitPercent,
    param_row$stopLossPercent,
    next_bar_entry = NEXT_BAR_ENTRY,
    symbol_name = symbol_name,
    return_trades_detail = FALSE
  )

  # 组装结果
  data.frame(
    Symbol = symbol_name,
    lookbackDays = as.integer(param_row$lookbackDays),
    minDropPercent = as.numeric(param_row$minDropPercent),
    takeProfitPercent = as.numeric(param_row$takeProfitPercent),
    stopLossPercent = as.numeric(param_row$stopLossPercent),
    Signal_Count = as.integer(result$Signal_Count),
    Trade_Count = as.integer(result$Trade_Count),
    TP_Count = as.integer(result$TP_Count),
    SL_Count = as.integer(result$SL_Count),
    Final_Capital = as.numeric(result$Final_Capital),
    Return_Percentage = as.numeric(result$Return_Percentage),
    Max_Drawdown = as.numeric(result$Max_Drawdown),
    Win_Rate = as.numeric(result$Win_Rate),
    Total_Fees = as.numeric(result$Total_Fees),
    Fee_Percentage = as.numeric(result$Fee_Percentage),
    BH_Return = as.numeric(result$BH_Return),
    Excess_Return = as.numeric(result$Excess_Return),
    stringsAsFactors = FALSE
  )
}

# ============================================================================
# 优化的并行执行策略：按时间框架分组
# ============================================================================

execute_optimization <- function() {
  cat("\n")
  cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
  cat("开始并行优化\n")
  cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

  # 尝试从检查点恢复
  checkpoint_data <- load_checkpoint("pepe_ultra")
  if (!is.null(checkpoint_data)) {
    all_results <- checkpoint_data$results
    completed_symbols <- unique(all_results$Symbol)
    remaining_symbols <- setdiff(pepe_symbols, completed_symbols)

    cat(sprintf("已完成 %d/%d 个时间框架\n",
                length(completed_symbols), length(pepe_symbols)))
    cat(sprintf("剩余: %s\n", paste(remaining_symbols, collapse = ", ")))
  } else {
    all_results <- list()
    remaining_symbols <- pepe_symbols
  }

  # 总计时
  total_start_time <- Sys.time()

  # 逐个时间框架处理（优化并行策略）
  for (idx in seq_along(remaining_symbols)) {
    symbol <- remaining_symbols[idx]

    cat(sprintf("\n[%d/%d] 处理 %s\n",
                idx, length(remaining_symbols), symbol))
    cat(paste(rep("-", 80), collapse = ""), "\n", sep = "")

    # 获取当前时间框架数据
    symbol_data <- cryptodata[[symbol]]
    cat(sprintf("数据行数: %s\n", format(nrow(symbol_data), big.mark = ",")))

    # 检测时间框架
    tf_mins <- detect_timeframe_minutes(symbol_data, use_cache = TRUE, cache_key = symbol)
    cat(sprintf("时间框架: %d 分钟\n", tf_mins))

    # 创建集群（每个时间框架独立集群）
    cat(sprintf("启动 %d 核并行集群...\n", CLUSTER_CORES))
    cl <- makeCluster(CLUSTER_CORES)

    # 导出必要的函数和数据到集群
    clusterEvalQ(cl, {
      suppressMessages({
        library(xts)
        library(RcppRoll)
      })
    })

    clusterExport(cl, c(
      "symbol_data",
      "symbol",
      "param_grid",
      "test_single_param",
      "backtest_strategy_optimized",
      "build_signals_optimized",
      "detect_timeframe_minutes",
      "NEXT_BAR_ENTRY",
      ".timeframe_cache"
    ), envir = environment())

    # 执行并行计算
    cat(sprintf("计算 %s 个参数组合...\n", format(nrow(param_grid), big.mark = ",")))

    symbol_start_time <- Sys.time()

    # 使用parLapply并行处理所有参数组合
    results_list <- parLapply(cl, 1:nrow(param_grid), function(i) {
      test_single_param(param_grid[i, ], symbol_data, symbol)
    })

    # 停止集群
    stopCluster(cl)

    # 合并结果
    symbol_results <- do.call(rbind, results_list)

    symbol_elapsed <- as.numeric(difftime(Sys.time(), symbol_start_time, units = "secs"))

    cat(sprintf("OK 完成! 耗时: %.1f 秒 (%.2f 分钟)\n",
                symbol_elapsed, symbol_elapsed / 60))

    # 统计
    valid_count <- sum(!is.na(symbol_results$Return_Percentage))
    trade_count <- sum(symbol_results$Trade_Count > 0)
    avg_return <- mean(symbol_results$Return_Percentage, na.rm = TRUE)

    cat(sprintf("  有效结果: %d/%d (%.1f%%)\n",
                valid_count, nrow(symbol_results),
                valid_count / nrow(symbol_results) * 100))
    cat(sprintf("  有交易: %d (%.1f%%)\n",
                trade_count, trade_count / valid_count * 100))
    cat(sprintf("  平均收益: %.2f%%\n", avg_return))

    # 添加到总结果
    all_results[[length(all_results) + 1]] <- symbol_results

    # 保存检查点
    combined_results <- do.call(rbind, all_results)
    save_checkpoint(combined_results, "pepe_ultra", list(
      completed_symbols = length(all_results),
      total_symbols = length(pepe_symbols),
      last_symbol = symbol
    ))

    # 内存清理
    gc(verbose = FALSE)
  }

  # 合并所有结果
  final_results <- do.call(rbind, all_results)

  total_elapsed <- as.numeric(difftime(Sys.time(), total_start_time, units = "secs"))

  cat("\n")
  cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
  cat("优化完成！\n")
  cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

  cat(sprintf("总耗时: %.1f 秒 (%.2f 分钟)\n",
              total_elapsed, total_elapsed / 60))
  cat(sprintf("总任务数: %s\n", format(nrow(final_results), big.mark = ",")))
  cat(sprintf("平均速度: %.2f 任务/秒\n", nrow(final_results) / total_elapsed))

  return(final_results)
}

# ============================================================================
# 主执行流程
# ============================================================================

cat("\n")
cat("预执行检查...\n")

# 检查RcppRoll包
if (!requireNamespace("RcppRoll", quietly = TRUE)) {
  cat("WARN  警告: RcppRoll 包未安装\n")
  cat("正在安装...\n")
  install.packages("RcppRoll", repos = "https://cloud.r-project.org/")
}

# 内存检查
check_memory("预执行")

# 快速性能测试
cat("\n运行快速性能测试（1个参数组合）...\n")
test_data <- cryptodata[["PEPEUSDT_15m"]]
test_start <- Sys.time()
test_result <- backtest_strategy_optimized(test_data, 3, 20, 10, 10, symbol_name = "PEPEUSDT_15m")
test_time <- as.numeric(difftime(Sys.time(), test_start, units = "secs"))

cat(sprintf("  测试耗时: %.3f 秒\n", test_time))
cat(sprintf("  信号数: %s\n", format(test_result$Signal_Count, big.mark = ",")))
cat(sprintf("  交易数: %d\n", test_result$Trade_Count))

# 预估总时间
estimated_total_secs <- test_time * total_tasks / (CLUSTER_CORES * 0.85)
estimated_minutes <- estimated_total_secs / 60

cat(sprintf("\n预估总执行时间: %.1f 分钟 (%.2f 小时)\n",
            estimated_minutes, estimated_minutes / 60))

if (estimated_minutes <= 60) {
  cat("OK 预估时间满足60分钟目标\n")
} else {
  cat("WARN  预估时间超过60分钟目标\n")
}

# 询问是否继续
cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat(sprintf("准备执行 %s 个回测任务\n", format(total_tasks, big.mark = ",")))
cat(sprintf("预计耗时: %.1f 分钟\n", estimated_minutes))
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

# 自动开始执行
cat("开始执行...\n")
Sys.sleep(2)  # 短暂延迟

# 执行优化
all_results <- execute_optimization()

# ============================================================================
# 保存结果
# ============================================================================

output_file <- "pepe_ultra_fast_results.csv"
cat(sprintf("\n保存结果到: %s\n", output_file))
write.csv(all_results, output_file, row.names = FALSE)

file_size_mb <- file.size(output_file) / 1024^2
cat(sprintf("文件大小: %.1f MB\n", file_size_mb))

# ============================================================================
# 结果分析
# ============================================================================

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("结果统计\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

# 基本统计
total_rows <- nrow(all_results)
valid_results <- all_results[!is.na(all_results$Return_Percentage), ]
valid_count <- nrow(valid_results)

cat(sprintf("总结果数: %s\n", format(total_rows, big.mark = ",")))
cat(sprintf("有效结果: %s (%.1f%%)\n",
            format(valid_count, big.mark = ","),
            valid_count / total_rows * 100))

if (valid_count > 0) {
  cat(sprintf("\n性能指标:\n"))
  cat(sprintf("  平均收益率: %.2f%%\n", mean(valid_results$Return_Percentage)))
  cat(sprintf("  最佳收益率: %.2f%%\n", max(valid_results$Return_Percentage)))
  cat(sprintf("  平均交易次数: %.1f\n", mean(valid_results$Trade_Count)))
  cat(sprintf("  平均信号数: %.1f\n", mean(valid_results$Signal_Count)))
  cat(sprintf("  平均胜率: %.2f%%\n", mean(valid_results$Win_Rate, na.rm = TRUE)))
  cat(sprintf("  平均手续费: %.2f USDT (%.3f%%)\n",
              mean(valid_results$Total_Fees, na.rm = TRUE),
              mean(valid_results$Fee_Percentage, na.rm = TRUE)))

  # 找出各时间框架最优参数
  cat("\n")
  cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
  cat("各时间框架最优参数\n")
  cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

  for (symbol in pepe_symbols) {
    sym_results <- valid_results[valid_results$Symbol == symbol, ]
    if (nrow(sym_results) > 0) {
      best_idx <- which.max(sym_results$Return_Percentage)
      best <- sym_results[best_idx, ]

      cat(sprintf("%s:\n", symbol))
      cat(sprintf("  参数: lookback=%dd, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                  best$lookbackDays, best$minDropPercent,
                  best$takeProfitPercent, best$stopLossPercent))
      cat(sprintf("  表现: 收益=%.2f%%, 交易=%d次, 胜率=%.1f%%, 最大回撤=%.2f%%\n",
                  best$Return_Percentage, best$Trade_Count,
                  best$Win_Rate, best$Max_Drawdown))
      cat(sprintf("  信号数: %d, 手续费: %.2f USDT (%.3f%%)\n\n",
                  best$Signal_Count, best$Total_Fees, best$Fee_Percentage))
    }
  }

  # Top 10 参数组合
  cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
  cat("Top 10 参数组合（按收益率）\n")
  cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

  top10 <- valid_results[order(-valid_results$Return_Percentage), ][1:10, ]

  for (i in 1:nrow(top10)) {
    row <- top10[i, ]
    cat(sprintf("%d. %s\n", i, row$Symbol))
    cat(sprintf("   参数: lookback=%dd, drop=%.0f%%, TP=%.0f%%, SL=%.0f%%\n",
                row$lookbackDays, row$minDropPercent,
                row$takeProfitPercent, row$stopLossPercent))
    cat(sprintf("   收益: %.2f%% | 交易: %d次 | 胜率: %.1f%% | 回撤: %.2f%%\n\n",
                row$Return_Percentage, row$Trade_Count,
                row$Win_Rate, row$Max_Drawdown))
  }
}

# 最终内存检查
check_memory("执行完成后")

# 清理检查点
if (ENABLE_CHECKPOINTS) {
  cat("\n清理检查点文件...\n")
  checkpoint_files <- list.files(pattern = "^checkpoint_.*\\.rds$")
  if (length(checkpoint_files) > 0) {
    file.remove(checkpoint_files)
    cat(sprintf("已删除 %d 个检查点文件\n", length(checkpoint_files)))
  }
}

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n", sep = "")
cat("全部完成！\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n", sep = "")

cat(sprintf("结果文件: %s\n", output_file))
cat("后续分析命令:\n")
cat(sprintf("  results <- read.csv('%s')\n", output_file))
cat("  summary(results$Return_Percentage)\n")
cat("  hist(results$Return_Percentage, breaks=50)\n\n")

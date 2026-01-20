# 读取TradingView的Excel文件
# 分析完整的策略参数

library(readxl)

# 读取Excel文件
file_path <- "c:/Users/ROG/Downloads/三日暴跌接针策略_BINANCE_PEPEUSDT_2025-10-27_df79a.xlsx"

cat("\n================================================================================\n")
cat("读取TradingView交易参数Excel文件\n")
cat("================================================================================\n\n")

# 获取所有sheet名称
sheet_names <- excel_sheets(file_path)
cat("Excel文件包含的Sheet:\n")
for (i in seq_along(sheet_names)) {
  cat(sprintf("  %d. %s\n", i, sheet_names[i]))
}
cat("\n")

# 读取所有sheet
for (sheet in sheet_names) {
  cat(rep("=", 100), "\n", sep="")
  cat(sprintf("Sheet: %s\n", sheet))
  cat(rep("=", 100), "\n\n", sep="")

  tryCatch({
    df <- read_excel(file_path, sheet = sheet)

    cat(sprintf("行数: %d\n", nrow(df)))
    cat(sprintf("列数: %d\n\n", ncol(df)))

    cat("列名:\n")
    for (col in names(df)) {
      cat(sprintf("  - %s\n", col))
    }
    cat("\n")

    # 显示前10行数据
    if (nrow(df) > 0) {
      cat("前10行数据:\n")
      print(head(df, 10))
      cat("\n")

      # 如果是交易列表，保存为CSV
      if (grepl("交易列表|Trade List|List of Trades", sheet, ignore.case = TRUE)) {
        csv_path <- "tv_trades_from_excel.csv"
        write.csv(df, csv_path, row.names = FALSE, fileEncoding = "UTF-8")
        cat(sprintf("OK 交易数据已保存: %s\n\n", csv_path))
      }

      # 如果是性能摘要
      if (grepl("性能摘要|Performance Summary|Overview", sheet, ignore.case = TRUE)) {
        cat("\n关键性能指标:\n")
        print(df)
        cat("\n")
      }
    }

  }, error = function(e) {
    cat(sprintf("FAIL 读取失败: %s\n\n", e$message))
  })

  cat("\n")
}

cat("完成！\n\n")

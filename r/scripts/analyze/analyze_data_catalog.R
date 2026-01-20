suppressMessages({
  library(xts)
})

load('data/liaochu.RData')

cat('\n分析数据源...\n')

all_info <- list()

for (ds_name in names(cryptodata)) {
  data <- cryptodata[[ds_name]]

  parts <- strsplit(ds_name, '_')[[1]]
  pair <- parts[1]
  timeframe <- parts[2]

  dates <- index(data)
  start_date <- as.character(dates[1])
  end_date <- as.character(dates[length(dates)])

  year_month <- format(dates, '%Y-%m')
  unique_months <- unique(year_month)

  all_info[[ds_name]] <- data.frame(
    dataset = ds_name,
    pair = pair,
    timeframe = timeframe,
    start_date = start_date,
    end_date = end_date,
    total_bars = nrow(data),
    total_months = length(unique_months),
    first_month = unique_months[1],
    last_month = unique_months[length(unique_months)],
    stringsAsFactors = FALSE
  )
}

result_df <- do.call(rbind, all_info)
rownames(result_df) <- NULL

output_file <- 'data_catalog/datasets_info.csv'
dir.create('data_catalog', showWarnings = FALSE, recursive = TRUE)
write.csv(result_df, output_file, row.names = FALSE)

cat(sprintf('\nOK 数据已导出到: %s\n', output_file))
cat(sprintf('OK 总数据集: %d\n', nrow(result_df)))
cat(sprintf('OK 币种数: %d\n', length(unique(result_df$pair))))
cat(sprintf('OK 时间周期数: %d\n', length(unique(result_df$timeframe))))

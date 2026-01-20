# 查询XRP数据起始时间
library(xts)

# 加载数据
load('data/liaochu.RData')

# 获取XRP数据集
xrp_datasets <- grep('^XRPUSDT_', names(cryptodata), value=TRUE)

cat('\nXRP数据集起始时间:\n')
cat('═════════════════════════════════════════════════════════════\n\n')

for(ds in sort(xrp_datasets)) {
  tryCatch({
    data <- cryptodata[[ds]]
    dates <- index(data)

    cat(sprintf('%s:\n', ds))
    cat(sprintf('  起始时间: %s\n', as.character(dates[1])))
    cat(sprintf('  结束时间: %s\n', as.character(dates[length(dates)])))

    # 计算历史年数
    start_year <- as.numeric(format(dates[1], '%Y'))
    end_year <- as.numeric(format(dates[length(dates)], '%Y'))
    years_diff <- end_year - start_year

    cat(sprintf('  历史年数: 约%d年\n\n', years_diff))

  }, error = function(e) {
    cat(sprintf('FAIL %s 查询失败: %s\n\n', ds, e$message))
  })
}
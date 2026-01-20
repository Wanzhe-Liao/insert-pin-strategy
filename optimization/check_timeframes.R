suppressMessages({
  library(xts)
})

load('data/liaochu.RData')

cat('\n')
cat('════════════════════════════════════════════════════════════════════════════\n')
cat('可用的交易对和时间周期\n')
cat('════════════════════════════════════════════════════════════════════════════\n\n')

dataset_names <- names(cryptodata)

for (name in dataset_names) {
  data <- cryptodata[[name]]
  cat(sprintf('%-20s  %8d条K线  %s 至 %s\n',
              name,
              nrow(data),
              as.character(index(data)[1]),
              as.character(index(data)[nrow(data)])))
}

cat('\n')
cat(sprintf('总计: %d个数据集\n\n', length(dataset_names)))

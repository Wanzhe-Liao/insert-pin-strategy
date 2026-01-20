# 检查数据结构
load("data/liaochu.RData")

cat("cryptodata的结构:\n")
print(str(cryptodata))

cat("\n\ncryptodata的类:\n")
print(class(cryptodata))

cat("\n\ncryptodata的名称:\n")
print(names(cryptodata))

if("PEPEUSDT_15m" %in% names(cryptodata)) {
  cat("\n\nPEPEUSDT_15m的结构:\n")
  print(str(cryptodata[["PEPEUSDT_15m"]]))

  cat("\n\nPEPEUSDT_15m的类:\n")
  print(class(cryptodata[["PEPEUSDT_15m"]]))

  cat("\n\nPEPEUSDT_15m的列名:\n")
  print(colnames(cryptodata[["PEPEUSDT_15m"]]))

  cat("\n\nPEPEUSDT_15m的前几行:\n")
  print(head(cryptodata[["PEPEUSDT_15m"]]))
}

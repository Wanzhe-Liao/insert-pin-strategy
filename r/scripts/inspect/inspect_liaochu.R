suppressMessages(library(xts))

path <- "data/liaochu.RData"
load(path)

objs <- ls()
cat("Objects:", paste(objs, collapse=", "), "\n")

inspect_xts <- function(x, name) {
  cat("  elem name:", name, " class:", paste(class(x), collapse=", "), "\n")
  if (xts::is.xts(x)) {
    cat("    rows:", nrow(x), " cols:", paste(colnames(x), collapse=", "), "\n")
    needed <- c("Open","High","Low","Close","Volume")
    has_needed <- all(needed %in% colnames(x))
    cat("    has_OHLCV:", has_needed, "\n")
    print(head(x, 3))
  } else if (is.data.frame(x)) {
    cat("    df rows:", nrow(x), " cols:", paste(colnames(x), collapse=", "), "\n")
    print(head(x, 3))
  } else {
    cat("    (non-xts/non-df)\n")
  }
}

for (n in objs) {
  x <- get(n)
  cat("Object:", n, "\n")
  cat("Class:", paste(class(x), collapse=", "), "\n")
  if (is.list(x)) {
    cat("List length:", length(x), "\n")
    nm <- names(x)
    cat("Names(head):", paste(head(nm, 20), collapse=", "), "\n")
    if (length(x) > 0) {
      for (i in seq_len(min(3, length(x)))) {
        inspect_xts(x[[i]], nm[i])
      }
    }
  } else {
    inspect_xts(x, n)
  }
  cat("-----\n")
}
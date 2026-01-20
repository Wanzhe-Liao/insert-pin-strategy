# ============================================================================
# Time Index Quality Audit
# ----------------------------------------------------------------------------
# Audits `data/liaochu.RData` -> `cryptodata` xts list:
# - index monotonicity / duplicates
# - expected bar interval vs actual diffs
# - largest gaps (missing bars)
#
# Outputs:
# - outputs/time_index_quality_summary.csv
# - docs/reports/time_index_quality_audit.md
# ============================================================================

suppressMessages({
  library(xts)
  library(data.table)
})

parse_timeframe_seconds <- function(tf) {
  if (is.na(tf) || is.null(tf) || tf == "") return(NA_real_)

  m <- regexec("^([0-9]+)([mhd])$", tf)
  g <- regmatches(tf, m)[[1]]
  if (length(g) != 3) return(NA_real_)

  value <- as.numeric(g[2])
  unit <- g[3]
  if (is.na(value) || value <= 0) return(NA_real_)

  switch(
    unit,
    m = value * 60,
    h = value * 3600,
    d = value * 86400,
    NA_real_
  )
}

parse_dataset_name <- function(dataset_name) {
  parts <- strsplit(dataset_name, "_", fixed = TRUE)[[1]]
  if (length(parts) < 2) {
    return(list(pair = dataset_name, timeframe = NA_character_))
  }
  list(pair = parts[1], timeframe = parts[length(parts)])
}

audit_one_dataset <- function(dataset_name, x) {
  meta <- parse_dataset_name(dataset_name)
  expected_step <- parse_timeframe_seconds(meta$timeframe)

  idx <- index(x)
  idx_num <- as.numeric(idx)
  n <- length(idx_num)

  if (n <= 1) {
    return(data.table(
      dataset = dataset_name,
      pair = meta$pair,
      timeframe = meta$timeframe,
      timezone = attr(idx, "tzone") %||% NA_character_,
      bars = n,
      start_time = if (n == 1) as.character(idx[1]) else NA_character_,
      end_time = if (n == 1) as.character(idx[1]) else NA_character_,
      expected_step_s = expected_step,
      min_step_s = NA_real_,
      median_step_s = NA_real_,
      max_step_s = NA_real_,
      non_increasing_steps = 0L,
      near_zero_steps = 0L,
      step_lt_expected = NA_integer_,
      step_eq_expected = NA_integer_,
      step_gt_expected = NA_integer_,
      max_gap_s = NA_real_
    ))
  }

  diffs <- diff(idx_num)
  tol <- 0.5

  non_increasing <- sum(diffs <= 0, na.rm = TRUE)
  near_zero <- sum(abs(diffs) < tol, na.rm = TRUE)

  if (!is.na(expected_step)) {
    lt_expected <- sum(diffs < (expected_step - tol), na.rm = TRUE)
    eq_expected <- sum(abs(diffs - expected_step) <= tol, na.rm = TRUE)
    gt_expected <- sum(diffs > (expected_step + tol), na.rm = TRUE)
  } else {
    lt_expected <- NA_integer_
    eq_expected <- NA_integer_
    gt_expected <- NA_integer_
  }

  data.table(
    dataset = dataset_name,
    pair = meta$pair,
    timeframe = meta$timeframe,
    timezone = attr(idx, "tzone") %||% NA_character_,
    bars = n,
    start_time = as.character(idx[1]),
    end_time = as.character(idx[n]),
    expected_step_s = expected_step,
    min_step_s = min(diffs, na.rm = TRUE),
    median_step_s = median(diffs, na.rm = TRUE),
    max_step_s = max(diffs, na.rm = TRUE),
    non_increasing_steps = as.integer(non_increasing),
    near_zero_steps = as.integer(near_zero),
    step_lt_expected = lt_expected,
    step_eq_expected = eq_expected,
    step_gt_expected = gt_expected,
    max_gap_s = max(diffs, na.rm = TRUE)
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

cat("Loading data/liaochu.RData ...\n")
load("data/liaochu.RData")
stopifnot(exists("cryptodata"))

dataset_names <- names(cryptodata)
cat(sprintf("Datasets: %d\n", length(dataset_names)))

rows <- vector("list", length(dataset_names))
for (i in seq_along(dataset_names)) {
  nm <- dataset_names[[i]]
  rows[[i]] <- audit_one_dataset(nm, cryptodata[[nm]])
  if (i %% 10 == 0) gc()
}

summary_dt <- rbindlist(rows, use.names = TRUE, fill = TRUE)
setorder(summary_dt, timeframe, pair)

dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
summary_csv <- "outputs/time_index_quality_summary.csv"
fwrite(summary_dt, summary_csv)
cat(sprintf("OK Wrote %s\n", summary_csv))

# Markdown report
total <- nrow(summary_dt)
bad_non_inc <- summary_dt[non_increasing_steps > 0, .N]
bad_near_zero <- summary_dt[near_zero_steps > 0, .N]
bad_step_mismatch <- summary_dt[!is.na(expected_step_s) & step_eq_expected < (bars - 1), .N]

worst_gaps <- summary_dt[order(-max_gap_s)][1:min(20, .N),
  .(dataset, timeframe, bars, max_gap_s, non_increasing_steps, near_zero_steps, step_gt_expected)]

md <- c(
  "# Time Index Quality Audit",
  "",
  "This report audits the time index of `cryptodata` (loaded from `data/liaochu.RData`).",
  "",
  sprintf("- Total datasets: %d", total),
  sprintf("- Datasets with non-increasing steps (diff<=0): %d", bad_non_inc),
  sprintf("- Datasets with near-zero steps (|diff|<0.5s): %d", bad_near_zero),
  sprintf("- Datasets with step mismatch vs expected (by name suffix): %d", bad_step_mismatch),
  "",
  "## Worst gaps (Top 20 by max gap seconds)",
  "",
  paste0("| dataset | tf | bars | max_gap_s | non_inc | near_zero | step_gt_expected |"),
  paste0("|---|---:|---:|---:|---:|---:|---:|")
)

for (i in seq_len(nrow(worst_gaps))) {
  r <- worst_gaps[i]
  md <- c(md, sprintf(
    "| %s | %s | %d | %.3f | %d | %d | %s |",
    r$dataset,
    r$timeframe,
    r$bars,
    r$max_gap_s,
    r$non_increasing_steps,
    r$near_zero_steps,
    ifelse(is.na(r$step_gt_expected), "", as.character(r$step_gt_expected))
  ))
}

dir.create(file.path("docs", "reports"), showWarnings = FALSE, recursive = TRUE)
report_md <- file.path("docs", "reports", "time_index_quality_audit.md")
writeLines(md, report_md, useBytes = TRUE)
cat(sprintf("OK Wrote %s\n", report_md))


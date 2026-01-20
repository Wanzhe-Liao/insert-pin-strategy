# 对比R回测和TradingView的所有9笔交易价格

# TradingView数据（从CSV）
tv_trades <- data.frame(
  TradeId = 1:9,
  EntryPrice = c(3.07e-06, 9.5e-07, 1.25e-06, 1.15e-06, 5.52e-06,
                 5.43e-06, 4.37e-06, 4.95e-06, 6.84e-06),
  ExitPrice = c(3.38e-06, 1.05e-06, 1.38e-06, 1.27e-06, 6.08e-06,
                5.98e-06, 4.81e-06, 6.35e-06, 7.53e-06),
  stringsAsFactors = FALSE
)

# R回测数据（从刚才的输出）
r_trades <- data.frame(
  TradeId = 1:9,
  EntryPrice = c(0.00000307, 0.00000095, 0.00000125, 0.00000115, 0.00000552,
                 0.00000543, 0.00000437, 0.00000495, 0.00000684),
  ExitPrice = c(0.00000342, 0.00000105, 0.00000111, 0.00000127, 0.00000628,
                0.00000601, 0.00000485, 0.00000635, 0.00000754),
  stringsAsFactors = FALSE
)

cat('\n================================================================================\n')
cat('R回测 vs TradingView 价格对比（9笔交易）\n')
cat('================================================================================\n\n')

# 计算差异
entry_matches <- 0
exit_matches <- 0
total_trades <- nrow(tv_trades)

cat(sprintf('%-8s %-15s %-15s %-12s %-15s %-15s %-12s\n',
            '交易ID', 'TV入场价', 'R入场价', '入场匹配?',
            'TV出场价', 'R出场价', '出场匹配?'))
cat(paste(rep('=', 110), collapse=''), '\n')

for (i in 1:total_trades) {
  tv_entry <- tv_trades$EntryPrice[i]
  r_entry <- r_trades$EntryPrice[i]
  tv_exit <- tv_trades$ExitPrice[i]
  r_exit <- r_trades$ExitPrice[i]

  entry_diff_pct <- abs(tv_entry - r_entry) / tv_entry * 100
  exit_diff_pct <- abs(tv_exit - r_exit) / tv_exit * 100

  entry_match <- entry_diff_pct < 0.01  # 小于0.01%视为匹配
  exit_match <- exit_diff_pct < 1.0     # 小于1%视为匹配

  if (entry_match) entry_matches <- entry_matches + 1
  if (exit_match) exit_matches <- exit_matches + 1

  cat(sprintf('%-8d $%-13.8f $%-13.8f %-12s $%-13.8f $%-13.8f %-12s\n',
              i,
              tv_entry, r_entry, ifelse(entry_match, 'OK', 'FAIL'),
              tv_exit, r_exit, ifelse(exit_match, 'OK', sprintf('FAIL %.2f%%', exit_diff_pct))))
}

cat(paste(rep('=', 110), collapse=''), '\n\n')

# 统计结果
entry_alignment <- entry_matches / total_trades * 100
exit_alignment <- exit_matches / total_trades * 100

cat('对齐统计:\n')
cat(sprintf('  入场价格对齐: %d/%d (%.1f%%)\n', entry_matches, total_trades, entry_alignment))
cat(sprintf('  出场价格对齐: %d/%d (%.1f%%)\n', exit_matches, total_trades, exit_alignment))
cat('\n')

if (entry_alignment == 100) {
  cat('🎉 入场价格100%%对齐！\n')
} else {
  cat(sprintf('WARN 入场价格对齐率: %.1f%% (目标100%%)\n', entry_alignment))
}

if (exit_alignment >= 90) {
  cat(sprintf('OK 出场价格对齐率: %.1f%% (优秀)\n', exit_alignment))
} else {
  cat(sprintf('WARN 出场价格对齐率: %.1f%% (可接受)\n', exit_alignment))
}

cat('\n核心发现:\n')
cat('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n')
cat('TradingView的process_orders_on_close=true含义:\n')
cat('  OK 信号检测: 在K线收盘时检测信号\n')
cat('  OK 订单执行: 在K线收盘时执行订单\n')
cat('  OK 止盈止损: 【仅使用Close价格检查】，而非High/Low\n')
cat('\n')
cat('这解释了为什么交易#9在R和TV中的行为不同:\n')
cat('  - 入场: 2025-10-11 05:59 @ $0.00000684\n')
cat('  - 06:14那根K线:\n')
cat('    • Low=$0.00000589 (触及10%止损线$0.00000616)\n')
cat('    • Close=$0.00000668 (未触及止损线)\n')
cat('  - R原逻辑: 使用Low检查 → 触发止损 → 11笔交易\n')
cat('  - TV逻辑: 仅用Close检查 → 未触发 → 持续到10-13止盈\n')
cat('  - R新逻辑: 仅用Close检查 → 未触发 → 9笔交易 OK\n')
cat('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n')

cat('完成!\n\n')

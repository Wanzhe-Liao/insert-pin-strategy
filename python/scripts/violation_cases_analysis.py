"""
违反规则的具体案例分析
识别并分析违反"平仓前不开新仓"规则的情况
"""

import pandas as pd
import numpy as np
from datetime import timedelta
from pathlib import Path

# 读取数据
OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

trades = pd.read_csv(OUTPUT_DIR / 'trades_tradingview_aligned.csv')
trades['EntryTime'] = pd.to_datetime(trades['EntryTime'])
trades['ExitTime'] = pd.to_datetime(trades['ExitTime'])
trades['PnLPercent'] = trades['PnLPercent'].str.rstrip('%').astype(float)

print("=" * 100)
print("违反规则的具体案例分析")
print("=" * 100)

# ============================================================================
# 案例1: HoldingBars = 0 的交易 (同一K线入场和出场)
# ============================================================================
print("\n" + "=" * 100)
print("案例类型1: 持仓0根K线的交易 (同一K线入场和出场)")
print("=" * 100)

zero_holding = trades[trades['HoldingBars'] == 0].copy()

print(f"\n找到 {len(zero_holding)} 笔持仓0根K线的交易:")
print(f"占总交易的: {len(zero_holding)/len(trades)*100:.2f}%\n")

if len(zero_holding) > 0:
    print("\n详细案例分析:\n")

    for idx, row in zero_holding.iterrows():
        print("-" * 100)
        print(f"\n【案例 {idx + 1}】交易 #{row['TradeId']}")
        print(f"{'='*100}")

        print(f"\n基本信息:")
        print(f"  入场时间: {row['EntryTime']}")
        print(f"  入场价格: {row['EntryPrice']:.10f} USDT")
        print(f"  出场时间: {row['ExitTime']}")
        print(f"  出场价格: {row['ExitPrice']:.10f} USDT")
        print(f"  出场原因: {row['ExitReason']}")

        print(f"\n交易表现:")
        print(f"  盈亏比例: {row['PnLPercent']:.2f}%")
        print(f"  盈亏金额: {row['PnLAmount']:.2f} USDT")
        print(f"  手续费: {row['TotalFee']:.2f} USDT")
        print(f"  持仓K线数: {row['HoldingBars']} 根 WARN")

        # 价格变化分析
        price_change = (row['ExitPrice'] - row['EntryPrice']) / row['EntryPrice'] * 100
        print(f"  价格变化: {price_change:+.2f}%")

        # 查看前后交易
        if idx > 0:
            prev_trade = trades.iloc[idx - 1]
            interval_from_prev = (row['EntryTime'] - prev_trade['ExitTime']).total_seconds() / 60
            print(f"\n与前一笔交易的关系:")
            print(f"  前一笔 #{prev_trade['TradeId']} 出场: {prev_trade['ExitTime']}")
            print(f"  前一笔出场原因: {prev_trade['ExitReason']}")
            print(f"  间隔时间: {interval_from_prev:.2f} 分钟")

        if idx < len(trades) - 1:
            next_trade = trades.iloc[idx + 1]
            interval_to_next = (next_trade['EntryTime'] - row['ExitTime']).total_seconds() / 60
            print(f"\n与后一笔交易的关系:")
            print(f"  后一笔 #{next_trade['TradeId']} 入场: {next_trade['EntryTime']}")
            print(f"  间隔时间: {interval_to_next:.2f} 分钟")

        # 判断原因
        print(f"\n可能原因分析:")
        if row['ExitReason'] in ['TP', 'SL']:
            print(f"  OK 在同一K线内触发了{row['ExitReason']}条件")
            if abs(row['PnLPercent']) >= 10:
                print(f"  OK 价格波动剧烈，单K线内涨跌幅达到止损/止盈条件")
        if row['ExitReason'] == 'SL_first_in_both':
            print(f"  WARN 特殊标记: 这是两个系统中第一笔止损交易")

        print()

# ============================================================================
# 案例2: 快速重入场 (间隔≤15分钟)
# ============================================================================
print("\n" + "=" * 100)
print("案例类型2: 快速重入场 (间隔≤15分钟)")
print("=" * 100)

trades['NextEntryTime'] = trades['EntryTime'].shift(-1)
trades['ReentryInterval'] = (trades['NextEntryTime'] - trades['ExitTime']).dt.total_seconds() / 60

quick_reentry = trades[trades['ReentryInterval'] <= 15].dropna(subset=['ReentryInterval']).copy()

print(f"\n找到 {len(quick_reentry)} 笔快速重入场的交易:")
print(f"占总交易的: {len(quick_reentry)/len(trades)*100:.2f}%\n")

if len(quick_reentry) > 0:
    # 按间隔排序
    quick_reentry_sorted = quick_reentry.sort_values('ReentryInterval')

    print("\n前10个最快重入场的案例:\n")

    for i, (idx, row) in enumerate(quick_reentry_sorted.head(10).iterrows()):
        next_trade = trades.iloc[idx + 1]

        print("-" * 100)
        print(f"\n【案例 {i + 1}】交易 #{row['TradeId']} → #{next_trade['TradeId']}")
        print(f"{'='*100}")

        print(f"\n出场信息:")
        print(f"  出场时间: {row['ExitTime']}")
        print(f"  出场价格: {row['ExitPrice']:.10f} USDT")
        print(f"  出场原因: {row['ExitReason']}")
        print(f"  盈亏: {row['PnLPercent']:+.2f}%")

        print(f"\n再入场信息:")
        print(f"  入场时间: {next_trade['EntryTime']}")
        print(f"  入场价格: {next_trade['EntryPrice']:.10f} USDT")
        print(f"  间隔时间: {row['ReentryInterval']:.2f} 分钟 WARN")

        # 价格对比
        price_change = (next_trade['EntryPrice'] - row['ExitPrice']) / row['ExitPrice'] * 100
        print(f"  价格变化: {price_change:+.2f}%")

        # 分析原因
        print(f"\n模式分析:")
        if row['ReentryInterval'] == 0:
            print(f"  WARN 同一K线再入场 - 可能是价格在K线内剧烈波动")
        elif row['ReentryInterval'] <= 15:
            print(f"  WARN 相邻K线再入场 - 可能是策略没有冷却期限制")

        if row['ExitReason'] == 'SL' and next_trade['EntryPrice'] < row['ExitPrice']:
            print(f"  NOTE 止损后价格继续下跌，可能是'抄底'行为")
        elif row['ExitReason'] == 'TP' and next_trade['EntryPrice'] < row['ExitPrice']:
            print(f"  NOTE 止盈后价格回落，可能是'追跌'行为")

        print()

# ============================================================================
# 案例3: 特定时间段的高频交易
# ============================================================================
print("\n" + "=" * 100)
print("案例类型3: 高频交易时段分析")
print("=" * 100)

# 找出1天内有3笔以上交易的日期
trades['Date'] = trades['EntryTime'].dt.date
daily_counts = trades.groupby('Date').size()
high_freq_days = daily_counts[daily_counts >= 3].sort_values(ascending=False)

print(f"\n找到 {len(high_freq_days)} 天有3笔或以上交易:\n")

for i, (date, count) in enumerate(high_freq_days.head(10).items()):
    print("-" * 100)
    print(f"\n【高频交易日 {i + 1}】{date} - {count} 笔交易")
    print(f"{'='*100}")

    day_trades = trades[trades['Date'] == date].copy()

    print(f"\n该日交易详情:")
    for j, (idx, trade) in enumerate(day_trades.iterrows()):
        print(f"\n  交易 {j + 1} (#{trade['TradeId']}):")
        print(f"    入场: {trade['EntryTime'].strftime('%H:%M')} @ {trade['EntryPrice']:.10f}")
        print(f"    出场: {trade['ExitTime'].strftime('%H:%M')} @ {trade['ExitPrice']:.10f}")
        print(f"    原因: {trade['ExitReason']}")
        print(f"    盈亏: {trade['PnLPercent']:+.2f}%")
        print(f"    持仓: {trade['HoldingBars']} 根K线")

    # 计算该日总盈亏
    day_pnl = day_trades['PnLPercent'].sum()
    day_pnl_amount = day_trades['PnLAmount'].sum()
    win_trades = (day_trades['PnLPercent'] > 0).sum()
    loss_trades = (day_trades['PnLPercent'] < 0).sum()

    print(f"\n  该日统计:")
    print(f"    总盈亏: {day_pnl:+.2f}% ({day_pnl_amount:+.2f} USDT)")
    print(f"    盈利交易: {win_trades} 笔")
    print(f"    亏损交易: {loss_trades} 笔")
    print(f"    当日胜率: {win_trades/count*100:.1f}%")

    # 分析交易间隔
    day_intervals = []
    for k in range(len(day_trades) - 1):
        exit_time = day_trades.iloc[k]['ExitTime']
        next_entry = day_trades.iloc[k + 1]['EntryTime']
        interval = (next_entry - exit_time).total_seconds() / 60
        day_intervals.append(interval)

    if day_intervals:
        print(f"\n  交易间隔:")
        print(f"    最小: {min(day_intervals):.1f} 分钟")
        print(f"    平均: {np.mean(day_intervals):.1f} 分钟")
        print(f"    最大: {max(day_intervals):.1f} 分钟")

    print()

# ============================================================================
# 案例4: TradingView规则验证
# ============================================================================
print("\n" + "=" * 100)
print("案例类型4: TradingView规则验证")
print("=" * 100)

# TradingView的9笔交易
tv_trades_data = [
    {'id': 1, 'entry': '2023-05-06 02:44', 'exit': '2023-05-06 03:29', 'pnl': 9.93},
    {'id': 2, 'entry': '2023-08-18 05:30', 'exit': '2023-08-18 06:00', 'pnl': 10.36},
    {'id': 3, 'entry': '2023-11-10 00:00', 'exit': '2023-11-11 07:59', 'pnl': 10.23},
    {'id': 4, 'entry': '2024-01-03 19:59', 'exit': '2024-01-04 00:15', 'pnl': 10.27},
    {'id': 5, 'entry': '2024-03-06 03:45', 'exit': '2024-03-06 04:59', 'pnl': 9.98},
    {'id': 6, 'entry': '2024-04-13 02:30', 'exit': '2024-04-13 03:29', 'pnl': 9.96},
    {'id': 7, 'entry': '2024-04-14 04:00', 'exit': '2024-04-14 05:44', 'pnl': 9.90},
    {'id': 8, 'entry': '2025-10-11 05:15', 'exit': '2025-10-11 05:30', 'pnl': 28.09},
    {'id': 9, 'entry': '2025-10-11 05:44', 'exit': '2025-10-13 02:15', 'pnl': 9.92},
]

tv_df = pd.DataFrame(tv_trades_data)
tv_df['entry'] = pd.to_datetime(tv_df['entry'])
tv_df['exit'] = pd.to_datetime(tv_df['exit'])
tv_df['next_entry'] = tv_df['entry'].shift(-1)
tv_df['interval_minutes'] = (tv_df['next_entry'] - tv_df['exit']).dt.total_seconds() / 60

print("\nTradingView交易间隔分析:\n")

for idx, row in tv_df.iterrows():
    if pd.notna(row['interval_minutes']):
        print(f"交易 #{row['id']} → #{tv_df.iloc[idx+1]['id']}:")
        print(f"  出场: {row['exit']}")
        print(f"  下一笔入场: {tv_df.iloc[idx+1]['entry']}")
        print(f"  间隔: {row['interval_minutes']:.2f} 分钟 ({row['interval_minutes']/1440:.2f} 天)")
        print()

print("\nTradingView规则验证结果:")
print(f"OK 最小间隔: {tv_df['interval_minutes'].min():.2f} 分钟")
print(f"OK 平均间隔: {tv_df['interval_minutes'].mean():.2f} 分钟 ({tv_df['interval_minutes'].mean()/1440:.2f} 天)")
print(f"OK 最大间隔: {tv_df['interval_minutes'].max():.2f} 分钟 ({tv_df['interval_minutes'].max()/1440:.2f} 天)")

# 检查是否有快速重入场
quick_tv = tv_df[tv_df['interval_minutes'] <= 60]
print(f"\n1小时内再入场: {len(quick_tv)} 笔")

if len(quick_tv) > 0:
    print("\n特别关注的快速重入场:")
    for idx, row in quick_tv.iterrows():
        next_trade = tv_df.iloc[idx + 1]
        print(f"  交易 #{row['id']} → #{next_trade['id']}: {row['interval_minutes']:.2f} 分钟")

# ============================================================================
# 生成违规案例汇总报告
# ============================================================================
print("\n" + "=" * 100)
print("违规案例汇总报告")
print("=" * 100)

summary = {
    '违规类型': [],
    '案例数量': [],
    '占比': [],
    '严重程度': [],
    '建议措施': []
}

# 类型1: 持仓0根K线
summary['违规类型'].append('持仓0根K线')
summary['案例数量'].append(len(zero_holding))
summary['占比'].append(f"{len(zero_holding)/len(trades)*100:.2f}%")
summary['严重程度'].append('高' if len(zero_holding) > 10 else '中')
summary['建议措施'].append('检查止损止盈触发逻辑，避免K线内反复触发')

# 类型2: 同一K线再入场
same_bar = trades[trades['ReentryInterval'] == 0]
summary['违规类型'].append('同一K线再入场')
summary['案例数量'].append(len(same_bar))
summary['占比'].append(f"{len(same_bar)/len(trades)*100:.2f}%")
summary['严重程度'].append('高')
summary['建议措施'].append('添加至少1根K线的冷却期')

# 类型3: 15分钟内再入场
summary['违规类型'].append('15分钟内再入场')
summary['案例数量'].append(len(quick_reentry))
summary['占比'].append(f"{len(quick_reentry)/len(trades)*100:.2f}%")
summary['严重程度'].append('中')
summary['建议措施'].append('考虑增加15-60分钟冷却期')

# 类型4: 高频交易日
summary['违规类型'].append('单日3笔以上交易')
summary['案例数量'].append(len(high_freq_days))
summary['占比'].append(f"{len(high_freq_days)/len(trades.groupby('Date').size())*100:.2f}%")
summary['严重程度'].append('低')
summary['建议措施'].append('设置每日最大交易次数限制')

summary_df = pd.DataFrame(summary)
print("\n" + summary_df.to_string(index=False))

# 保存报告
summary_df.to_csv(OUTPUT_DIR / '违规案例汇总报告.csv', index=False, encoding='utf-8-sig')
print("\n已保存: 违规案例汇总报告.csv")

# 保存详细案例
if len(zero_holding) > 0:
    zero_holding.to_csv(OUTPUT_DIR / '持仓0根K线案例.csv', index=False, encoding='utf-8-sig')
    print("已保存: 持仓0根K线案例.csv")

if len(quick_reentry) > 0:
    quick_reentry.to_csv(OUTPUT_DIR / '快速重入场案例.csv', index=False, encoding='utf-8-sig')
    print("已保存: 快速重入场案例.csv")

print("\n" + "=" * 100)
print("案例分析完成!")
print("=" * 100)

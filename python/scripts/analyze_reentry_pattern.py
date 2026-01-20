"""
快速重入场模式分析
分析R回测中的"出场后立即再入场"行为
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import timedelta
import warnings
warnings.filterwarnings('ignore')

# 读取数据
print("=" * 80)
print("快速重入场模式分析")
print("=" * 80)

OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 1. 读取R的交易数据
trades = pd.read_csv(OUTPUT_DIR / 'trades_tradingview_aligned.csv')
trades['EntryTime'] = pd.to_datetime(trades['EntryTime'])
trades['ExitTime'] = pd.to_datetime(trades['ExitTime'])
trades['PnLPercent'] = trades['PnLPercent'].str.rstrip('%').astype(float)

print(f"\nR回测交易数: {len(trades)}")

# 2. 读取卖出信号数据
sell_signals = pd.read_csv(OUTPUT_DIR / 'sell_signals_detail.csv')
sell_signals['Timestamp'] = pd.to_datetime(sell_signals['Timestamp'])

print(f"卖出信号数: {len(sell_signals)}")

# ============================================================================
# 分析1: 统计"出场后立即再入场"的情况
# ============================================================================
print("\n" + "=" * 80)
print("分析1: 快速重入场统计")
print("=" * 80)

# 计算交易之间的间隔
trades['NextEntryTime'] = trades['EntryTime'].shift(-1)
trades['ReentryInterval'] = (trades['NextEntryTime'] - trades['ExitTime']).dt.total_seconds() / 60  # 转换为分钟

# 定义"立即"：同一K线或相邻K线（15分钟内）
immediate_reentry = trades[trades['ReentryInterval'] <= 15].copy()
same_bar_reentry = trades[trades['ReentryInterval'] == 0].copy()
adjacent_bar_reentry = trades[(trades['ReentryInterval'] > 0) & (trades['ReentryInterval'] <= 15)].copy()

print(f"\n快速重入场统计:")
print(f"- 同一K线再入场 (间隔=0分钟): {len(same_bar_reentry)} 笔 ({len(same_bar_reentry)/len(trades)*100:.2f}%)")
print(f"- 相邻K线再入场 (间隔≤15分钟): {len(adjacent_bar_reentry)} 笔 ({len(adjacent_bar_reentry)/len(trades)*100:.2f}%)")
print(f"- 快速再入场总计 (间隔≤15分钟): {len(immediate_reentry)} 笔 ({len(immediate_reentry)/len(trades)*100:.2f}%)")

# 统计HoldingBars=0的交易
zero_holding_trades = trades[trades['HoldingBars'] == 0]
print(f"\n持仓0根K线的交易: {len(zero_holding_trades)} 笔 ({len(zero_holding_trades)/len(trades)*100:.2f}%)")

# ============================================================================
# 分析2: 交易间隔分布
# ============================================================================
print("\n" + "=" * 80)
print("分析2: 交易间隔分布")
print("=" * 80)

# 计算间隔的各种分位数
valid_intervals = trades['ReentryInterval'].dropna()

print(f"\n交易间隔统计 (分钟):")
print(f"- 最小间隔: {valid_intervals.min():.2f} 分钟")
print(f"- 第25百分位: {valid_intervals.quantile(0.25):.2f} 分钟")
print(f"- 中位数: {valid_intervals.median():.2f} 分钟")
print(f"- 第75百分位: {valid_intervals.quantile(0.75):.2f} 分钟")
print(f"- 最大间隔: {valid_intervals.max():.2f} 分钟 ({valid_intervals.max()/1440:.2f} 天)")

# 统计不同时间段的交易数
interval_15min = (valid_intervals <= 15).sum()
interval_1hour = ((valid_intervals > 15) & (valid_intervals <= 60)).sum()
interval_1day = ((valid_intervals > 60) & (valid_intervals <= 1440)).sum()
interval_longer = (valid_intervals > 1440).sum()

print(f"\n交易间隔分组:")
print(f"- ≤15分钟 (立即): {interval_15min} 笔 ({interval_15min/len(valid_intervals)*100:.2f}%)")
print(f"- 15分钟-1小时: {interval_1hour} 笔 ({interval_1hour/len(valid_intervals)*100:.2f}%)")
print(f"- 1小时-1天: {interval_1day} 笔 ({interval_1day/len(valid_intervals)*100:.2f}%)")
print(f"- >1天: {interval_longer} 笔 ({interval_longer/len(valid_intervals)*100:.2f}%)")

# ============================================================================
# 分析3: 识别"同一K线平仓又开仓"的具体案例
# ============================================================================
print("\n" + "=" * 80)
print("分析3: 同一K线平仓又开仓的具体案例")
print("=" * 80)

if len(same_bar_reentry) > 0:
    print(f"\n找到 {len(same_bar_reentry)} 笔同一K线再入场的交易:")
    print("\n详细列表:")

    for idx, row in same_bar_reentry.iterrows():
        next_trade = trades.iloc[idx + 1] if idx + 1 < len(trades) else None

        print(f"\n交易 #{row['TradeId']}:")
        print(f"  出场时间: {row['ExitTime']}")
        print(f"  出场价格: {row['ExitPrice']:.10f}")
        print(f"  出场原因: {row['ExitReason']}")
        print(f"  盈亏: {row['PnLPercent']:.2f}%")

        if next_trade is not None:
            print(f"  → 下一笔 #{next_trade['TradeId']}:")
            print(f"     入场时间: {next_trade['EntryTime']}")
            print(f"     入场价格: {next_trade['EntryPrice']:.10f}")
            print(f"     间隔: {row['ReentryInterval']:.2f} 分钟 (同一K线!)")
else:
    print("\n未找到同一K线再入场的交易")

# 查看HoldingBars=0的交易详情
if len(zero_holding_trades) > 0:
    print(f"\n\n持仓0根K线的交易详情:")
    print("-" * 80)
    for idx, row in zero_holding_trades.iterrows():
        print(f"\n交易 #{row['TradeId']}:")
        print(f"  入场: {row['EntryTime']} @ {row['EntryPrice']:.10f}")
        print(f"  出场: {row['ExitTime']} @ {row['ExitPrice']:.10f}")
        print(f"  原因: {row['ExitReason']}")
        print(f"  盈亏: {row['PnLPercent']:.2f}%")
        print(f"  持仓K线数: {row['HoldingBars']}")

# ============================================================================
# 分析4: TradingView的交易间隔
# ============================================================================
print("\n" + "=" * 80)
print("分析4: TradingView交易间隔 (从差异报告提取)")
print("=" * 80)

# 从报告中提取的TradingView 9笔交易
tv_trades = [
    {'entry': '2023-05-06 02:44', 'exit': '2023-05-06 03:29'},
    {'entry': '2023-08-18 05:30', 'exit': '2023-08-18 06:00'},
    {'entry': '2023-11-10 00:00', 'exit': '2023-11-11 07:59'},
    {'entry': '2024-01-03 19:59', 'exit': '2024-01-04 00:15'},
    {'entry': '2024-03-06 03:45', 'exit': '2024-03-06 04:59'},
    {'entry': '2024-04-13 02:30', 'exit': '2024-04-13 03:29'},
    {'entry': '2024-04-14 04:00', 'exit': '2024-04-14 05:44'},
    {'entry': '2025-10-11 05:15', 'exit': '2025-10-11 05:30'},
    {'entry': '2025-10-11 05:44', 'exit': '2025-10-13 02:15'},
]

tv_df = pd.DataFrame(tv_trades)
tv_df['entry'] = pd.to_datetime(tv_df['entry'])
tv_df['exit'] = pd.to_datetime(tv_df['exit'])

tv_df['next_entry'] = tv_df['entry'].shift(-1)
tv_df['interval_minutes'] = (tv_df['next_entry'] - tv_df['exit']).dt.total_seconds() / 60

print("\nTradingView交易间隔:")
valid_tv_intervals = tv_df['interval_minutes'].dropna()

for i, interval in enumerate(valid_tv_intervals):
    print(f"交易 {i+1} → 交易 {i+2}: {interval:.2f} 分钟 ({interval/1440:.2f} 天)")

print(f"\nTradingView间隔统计:")
print(f"- 最小间隔: {valid_tv_intervals.min():.2f} 分钟")
print(f"- 最大间隔: {valid_tv_intervals.max():.2f} 分钟 ({valid_tv_intervals.max()/1440:.2f} 天)")
print(f"- 平均间隔: {valid_tv_intervals.mean():.2f} 分钟 ({valid_tv_intervals.mean()/1440:.2f} 天)")

# ============================================================================
# 分析5: 验证"平仓前不开新仓"规则
# ============================================================================
print("\n" + "=" * 80)
print("分析5: 验证'平仓前不开新仓'规则")
print("=" * 80)

# 检查R系统是否有持仓重叠
overlapping_trades = []

for i in range(len(trades) - 1):
    current_trade = trades.iloc[i]
    next_trade = trades.iloc[i + 1]

    # 如果下一笔交易的入场时间早于当前交易的出场时间，则有重叠
    if next_trade['EntryTime'] < current_trade['ExitTime']:
        overlapping_trades.append({
            'trade1_id': current_trade['TradeId'],
            'trade1_entry': current_trade['EntryTime'],
            'trade1_exit': current_trade['ExitTime'],
            'trade2_id': next_trade['TradeId'],
            'trade2_entry': next_trade['EntryTime'],
            'overlap_minutes': (current_trade['ExitTime'] - next_trade['EntryTime']).total_seconds() / 60
        })

if len(overlapping_trades) > 0:
    print(f"\n发现 {len(overlapping_trades)} 笔持仓重叠的交易 (违反规则!):")
    for overlap in overlapping_trades[:10]:  # 只显示前10笔
        print(f"\n交易 #{overlap['trade1_id']} 与 #{overlap['trade2_id']} 重叠:")
        print(f"  交易1: {overlap['trade1_entry']} → {overlap['trade1_exit']}")
        print(f"  交易2: {overlap['trade2_entry']} 入场")
        print(f"  重叠时长: {overlap['overlap_minutes']:.2f} 分钟")
else:
    print("\nR系统遵循'平仓前不开新仓'规则 OK")

# TradingView的规则验证
print("\n\nTradingView系统规则验证:")
tv_overlapping = []

for i in range(len(tv_df) - 1):
    current = tv_df.iloc[i]
    next_trade = tv_df.iloc[i + 1]

    if next_trade['entry'] < current['exit']:
        tv_overlapping.append(i)

if len(tv_overlapping) > 0:
    print(f"发现 {len(tv_overlapping)} 笔持仓重叠的交易")
else:
    print("TradingView严格遵循'平仓前不开新仓'规则 OK")

# ============================================================================
# 分析6: 建议的冷却期参数
# ============================================================================
print("\n" + "=" * 80)
print("分析6: 基于TradingView数据反推冷却期参数")
print("=" * 80)

print("\n基于TradingView的最小间隔:")
tv_min_interval = valid_tv_intervals.min()
print(f"- 最小间隔: {tv_min_interval:.2f} 分钟 ({tv_min_interval/60:.2f} 小时)")

print("\n建议的冷却期设置:")
print(f"- 保守策略: {tv_min_interval:.0f} 分钟 (与TV最小间隔一致)")
print(f"- 中等策略: {valid_tv_intervals.quantile(0.25):.0f} 分钟 (TV第25百分位)")
print(f"- 激进策略: 15 分钟 (仅避免同一K线重入)")

# 计算如果应用冷却期，R系统会减少多少交易
print("\n\n如果在R系统应用冷却期，预计影响:")

for cooldown in [15, 60, 240, tv_min_interval]:
    filtered_trades = valid_intervals[valid_intervals > cooldown]
    reduction = len(valid_intervals) - len(filtered_trades)
    print(f"- 冷却期 {cooldown:.0f} 分钟: 减少 {reduction} 笔交易 ({reduction/len(valid_intervals)*100:.2f}%)")

# ============================================================================
# 生成汇总表
# ============================================================================
print("\n" + "=" * 80)
print("汇总表: 快速重入场统计")
print("=" * 80)

summary_data = {
    '指标': [
        '总交易数',
        '同一K线再入场',
        '相邻K线再入场(≤15分钟)',
        '1小时内再入场',
        '1天内再入场',
        '持仓0根K线交易',
        '最小再入场间隔',
        '中位再入场间隔',
    ],
    'R系统数量': [
        len(trades),
        len(same_bar_reentry),
        len(adjacent_bar_reentry),
        interval_15min + interval_1hour,
        interval_15min + interval_1hour + interval_1day,
        len(zero_holding_trades),
        f"{valid_intervals.min():.2f} 分钟",
        f"{valid_intervals.median():.2f} 分钟",
    ],
    'R系统占比': [
        '100%',
        f"{len(same_bar_reentry)/len(trades)*100:.2f}%",
        f"{len(adjacent_bar_reentry)/len(trades)*100:.2f}%",
        f"{(interval_15min + interval_1hour)/len(valid_intervals)*100:.2f}%",
        f"{(interval_15min + interval_1hour + interval_1day)/len(valid_intervals)*100:.2f}%",
        f"{len(zero_holding_trades)/len(trades)*100:.2f}%",
        '-',
        '-',
    ],
    'TradingView参考': [
        '9',
        '可能0',
        '可能1 (第8→9笔)',
        '-',
        '-',
        '-',
        f"{valid_tv_intervals.min():.2f} 分钟",
        f"{valid_tv_intervals.median():.2f} 分钟",
    ]
}

summary_df = pd.DataFrame(summary_data)
print("\n" + summary_df.to_string(index=False))

# 保存详细结果
print("\n" + "=" * 80)
print("保存分析结果...")
print("=" * 80)

# 保存快速重入场的交易列表
immediate_reentry_with_context = []

for idx, row in immediate_reentry.iterrows():
    next_trade = trades.iloc[idx + 1] if idx + 1 < len(trades) else None

    if next_trade is not None:
        immediate_reentry_with_context.append({
            'ExitTradeId': row['TradeId'],
            'ExitTime': row['ExitTime'],
            'ExitPrice': row['ExitPrice'],
            'ExitReason': row['ExitReason'],
            'ExitPnL': row['PnLPercent'],
            'ReentryTradeId': next_trade['TradeId'],
            'ReentryTime': next_trade['EntryTime'],
            'ReentryPrice': next_trade['EntryPrice'],
            'IntervalMinutes': row['ReentryInterval'],
            'HoldingBarsBeforeExit': row['HoldingBars'],
        })

immediate_reentry_df = pd.DataFrame(immediate_reentry_with_context)
immediate_reentry_df.to_csv(OUTPUT_DIR / '快速重入场案例.csv', index=False, encoding='utf-8-sig')
print("\n已保存: 快速重入场案例.csv")

# 保存交易间隔分析
interval_analysis = trades[['TradeId', 'ExitTime', 'ReentryInterval']].dropna()
interval_analysis.to_csv(OUTPUT_DIR / '交易间隔分析.csv', index=False, encoding='utf-8-sig')
print("已保存: 交易间隔分析.csv")

# 保存汇总表
summary_df.to_csv(OUTPUT_DIR / '快速重入场统计汇总.csv', index=False, encoding='utf-8-sig')
print("已保存: 快速重入场统计汇总.csv")

print("\n" + "=" * 80)
print("分析完成!")
print("=" * 80)

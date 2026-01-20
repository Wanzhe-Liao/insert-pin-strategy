"""
交易间隔可视化分析
生成交易间隔分布图和时间线图
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import timedelta
import warnings
from pathlib import Path
warnings.filterwarnings('ignore')

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'Arial Unicode MS']
plt.rcParams['axes.unicode_minus'] = False

OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 读取数据
trades = pd.read_csv(OUTPUT_DIR / 'trades_tradingview_aligned.csv')
trades['EntryTime'] = pd.to_datetime(trades['EntryTime'])
trades['ExitTime'] = pd.to_datetime(trades['ExitTime'])
trades['PnLPercent'] = trades['PnLPercent'].str.rstrip('%').astype(float)

# 计算交易间隔
trades['NextEntryTime'] = trades['EntryTime'].shift(-1)
trades['ReentryInterval'] = (trades['NextEntryTime'] - trades['ExitTime']).dt.total_seconds() / 60

valid_intervals = trades['ReentryInterval'].dropna()

# ============================================================================
# 图1: 交易间隔分布直方图
# ============================================================================
fig, axes = plt.subplots(2, 2, figsize=(16, 12))
fig.suptitle('R回测系统交易间隔分布分析', fontsize=16, fontweight='bold')

# 子图1: 全范围间隔分布
ax1 = axes[0, 0]
bins = [0, 15, 60, 240, 1440, 10080, valid_intervals.max()]
labels = ['0-15分钟\n(立即)', '15分钟-1小时', '1-4小时', '4小时-1天', '1-7天', f'7天+']
colors = ['#ff4444', '#ff8844', '#ffbb44', '#ffdd44', '#88cc44', '#44aa44']

counts, _ = np.histogram(valid_intervals, bins=bins)
x_pos = np.arange(len(labels))
bars = ax1.bar(x_pos, counts, color=colors, edgecolor='black', linewidth=1.5, alpha=0.8)

ax1.set_xlabel('交易间隔区间', fontsize=12, fontweight='bold')
ax1.set_ylabel('交易数量', fontsize=12, fontweight='bold')
ax1.set_title('交易间隔分布 (全范围)', fontsize=14, fontweight='bold')
ax1.set_xticks(x_pos)
ax1.set_xticklabels(labels, rotation=45, ha='right')
ax1.grid(True, alpha=0.3, axis='y')

# 在柱子上添加数值和百分比
for i, (bar, count) in enumerate(zip(bars, counts)):
    height = bar.get_height()
    percentage = count / len(valid_intervals) * 100
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(count)}\n({percentage:.1f}%)',
             ha='center', va='bottom', fontsize=10, fontweight='bold')

# 子图2: 聚焦快速重入场 (0-60分钟)
ax2 = axes[0, 1]
short_intervals = valid_intervals[valid_intervals <= 60]
bins_short = [0, 5, 10, 15, 20, 30, 45, 60]
ax2.hist(short_intervals, bins=bins_short, color='#ff6666', edgecolor='black', linewidth=1.5, alpha=0.8)
ax2.axvline(x=15, color='red', linestyle='--', linewidth=2, label='15分钟阈值 (K线周期)')
ax2.set_xlabel('交易间隔 (分钟)', fontsize=12, fontweight='bold')
ax2.set_ylabel('交易数量', fontsize=12, fontweight='bold')
ax2.set_title(f'快速重入场分布 (≤1小时)\n总计: {len(short_intervals)} 笔', fontsize=14, fontweight='bold')
ax2.grid(True, alpha=0.3)
ax2.legend(fontsize=11)

# 添加统计文本
stats_text = f'平均间隔: {short_intervals.mean():.1f}分钟\n中位数: {short_intervals.median():.1f}分钟'
ax2.text(0.98, 0.98, stats_text, transform=ax2.transAxes,
         fontsize=11, verticalalignment='top', horizontalalignment='right',
         bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))

# 子图3: 累积分布函数 (CDF)
ax3 = axes[1, 0]
sorted_intervals = np.sort(valid_intervals)
cumulative = np.arange(1, len(sorted_intervals) + 1) / len(sorted_intervals) * 100

ax3.plot(sorted_intervals, cumulative, linewidth=2.5, color='#2166ac')
ax3.axhline(y=50, color='red', linestyle='--', linewidth=1.5, label='中位数')
ax3.axvline(x=15, color='orange', linestyle='--', linewidth=1.5, label='15分钟 (K线周期)')
ax3.axvline(x=1440, color='green', linestyle='--', linewidth=1.5, label='1天')

ax3.set_xlabel('交易间隔 (分钟, 对数刻度)', fontsize=12, fontweight='bold')
ax3.set_ylabel('累积百分比 (%)', fontsize=12, fontweight='bold')
ax3.set_title('交易间隔累积分布', fontsize=14, fontweight='bold')
ax3.set_xscale('log')
ax3.grid(True, alpha=0.3, which='both')
ax3.legend(fontsize=11)

# 添加关键百分位点
percentiles = [25, 50, 75, 90, 95]
for p in percentiles:
    value = np.percentile(valid_intervals, p)
    ax3.scatter([value], [p], s=100, c='red', zorder=5)
    ax3.annotate(f'P{p}: {value:.0f}分',
                xy=(value, p), xytext=(10, 10),
                textcoords='offset points', fontsize=9,
                bbox=dict(boxstyle='round,pad=0.3', facecolor='yellow', alpha=0.7))

# 子图4: 箱线图对比
ax4 = axes[1, 1]

# 按时间段分组
intervals_by_period = {
    '0-15分钟\n(立即)': valid_intervals[valid_intervals <= 15],
    '15分钟-\n1小时': valid_intervals[(valid_intervals > 15) & (valid_intervals <= 60)],
    '1小时-\n1天': valid_intervals[(valid_intervals > 60) & (valid_intervals <= 1440)],
    '1天以上': valid_intervals[valid_intervals > 1440]
}

data_to_plot = [data.values for data in intervals_by_period.values()]
positions = range(1, len(intervals_by_period) + 1)

bp = ax4.boxplot(data_to_plot, positions=positions, widths=0.6,
                 patch_artist=True, showmeans=True,
                 meanprops=dict(marker='D', markerfacecolor='red', markersize=8))

# 设置颜色
colors_box = ['#ff4444', '#ff8844', '#ffbb44', '#88cc44']
for patch, color in zip(bp['boxes'], colors_box):
    patch.set_facecolor(color)
    patch.set_alpha(0.7)

ax4.set_ylabel('交易间隔 (分钟, 对数刻度)', fontsize=12, fontweight='bold')
ax4.set_title('交易间隔箱线图对比', fontsize=14, fontweight='bold')
ax4.set_xticks(positions)
ax4.set_xticklabels(intervals_by_period.keys(), fontsize=10)
ax4.set_yscale('log')
ax4.grid(True, alpha=0.3, axis='y')

plt.tight_layout()
plt.savefig(OUTPUT_DIR / '交易间隔分布图.png', dpi=300, bbox_inches='tight')
print("已保存: outputs/交易间隔分布图.png")
plt.close()

# ============================================================================
# 图2: 时间线图 - 显示交易密度随时间变化
# ============================================================================
fig, axes = plt.subplots(3, 1, figsize=(18, 14))
fig.suptitle('R回测系统交易时间线分析', fontsize=16, fontweight='bold')

# 子图1: 交易时间线
ax1 = axes[0]

for idx, row in trades.iterrows():
    color = '#2ca02c' if row['PnLPercent'] > 0 else '#d62728'
    # 绘制持仓期间的横线
    ax1.plot([row['EntryTime'], row['ExitTime']], [idx, idx],
             linewidth=2, color=color, alpha=0.6)
    # 标记入场和出场点
    ax1.scatter(row['EntryTime'], idx, c='green', s=30, marker='o', zorder=5)
    ax1.scatter(row['ExitTime'], idx, c='red', s=30, marker='s', zorder=5)

# 标记快速重入场
immediate_reentries = trades[trades['ReentryInterval'] <= 15].index
for idx in immediate_reentries:
    ax1.axhline(y=idx, color='orange', linestyle='--', alpha=0.3, linewidth=1)

ax1.set_xlabel('时间', fontsize=12, fontweight='bold')
ax1.set_ylabel('交易序号', fontsize=12, fontweight='bold')
ax1.set_title(f'交易持仓时间线 (绿点=入场, 红方块=出场, 橙色虚线=快速重入场)', fontsize=13)
ax1.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
ax1.grid(True, alpha=0.3)

# 子图2: 交易密度热力图
ax2 = axes[1]

# 按月统计交易数
trades['YearMonth'] = trades['EntryTime'].dt.to_period('M')
monthly_counts = trades.groupby('YearMonth').size()

months = [pd.Period(m).to_timestamp() for m in monthly_counts.index]
counts = monthly_counts.values

bars = ax2.bar(months, counts, width=25, color='steelblue', edgecolor='black', linewidth=0.5, alpha=0.8)

# 高亮交易密集月份
max_count = counts.max()
for bar, count in zip(bars, counts):
    if count > max_count * 0.7:
        bar.set_color('#ff4444')

ax2.set_xlabel('时间', fontsize=12, fontweight='bold')
ax2.set_ylabel('每月交易数', fontsize=12, fontweight='bold')
ax2.set_title('交易密度随时间变化 (红色=高密度月份)', fontsize=13)
ax2.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
ax2.grid(True, alpha=0.3, axis='y')

# 添加平均线
mean_count = counts.mean()
ax2.axhline(y=mean_count, color='green', linestyle='--', linewidth=2,
           label=f'平均: {mean_count:.1f} 笔/月')
ax2.legend(fontsize=11)

# 子图3: 交易间隔随时间变化
ax3 = axes[2]

interval_data = trades[['ExitTime', 'ReentryInterval']].dropna()
colors_scatter = ['#ff4444' if x <= 15 else '#4444ff' for x in interval_data['ReentryInterval']]

scatter = ax3.scatter(interval_data['ExitTime'], interval_data['ReentryInterval'],
                     c=colors_scatter, s=50, alpha=0.6, edgecolors='black', linewidth=0.5)

ax3.axhline(y=15, color='red', linestyle='--', linewidth=2, label='15分钟阈值 (红=快速重入场)')
ax3.axhline(y=1440, color='green', linestyle='--', linewidth=2, label='1天')

ax3.set_xlabel('出场时间', fontsize=12, fontweight='bold')
ax3.set_ylabel('再入场间隔 (分钟, 对数刻度)', fontsize=12, fontweight='bold')
ax3.set_title('交易间隔随时间变化', fontsize=13)
ax3.set_yscale('log')
ax3.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
ax3.grid(True, alpha=0.3)
ax3.legend(fontsize=11)

plt.tight_layout()
plt.savefig(OUTPUT_DIR / '交易时间线分析.png', dpi=300, bbox_inches='tight')
print("已保存: outputs/交易时间线分析.png")
plt.close()

# ============================================================================
# 图3: 对比TradingView和R的交易间隔
# ============================================================================
fig, ax = plt.subplots(1, 1, figsize=(14, 8))

# TradingView数据
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
tv_intervals = tv_df['interval_minutes'].dropna()

# 创建箱线图对比
data_to_plot = [valid_intervals.values, tv_intervals.values]
labels = [f'R系统\n({len(valid_intervals)} 个间隔)', f'TradingView\n({len(tv_intervals)} 个间隔)']

bp = ax.boxplot(data_to_plot, labels=labels, widths=0.5,
               patch_artist=True, showmeans=True,
               meanprops=dict(marker='D', markerfacecolor='red', markersize=10))

# 设置颜色
bp['boxes'][0].set_facecolor('#ff6666')
bp['boxes'][1].set_facecolor('#6666ff')
for box in bp['boxes']:
    box.set_alpha(0.7)

ax.set_ylabel('交易间隔 (分钟, 对数刻度)', fontsize=13, fontweight='bold')
ax.set_title('TradingView vs R系统: 交易间隔对比', fontsize=15, fontweight='bold')
ax.set_yscale('log')
ax.grid(True, alpha=0.3, axis='y')

# 添加统计信息
stats_text = f"""
R系统统计:
  最小: {valid_intervals.min():.1f} 分钟
  中位数: {valid_intervals.median():.1f} 分钟
  平均: {valid_intervals.mean():.1f} 分钟
  最大: {valid_intervals.max():.1f} 分钟

TradingView统计:
  最小: {tv_intervals.min():.1f} 分钟
  中位数: {tv_intervals.median():.1f} 分钟
  平均: {tv_intervals.mean():.1f} 分钟
  最大: {tv_intervals.max():.1f} 分钟
"""

ax.text(0.02, 0.98, stats_text, transform=ax.transAxes,
       fontsize=10, verticalalignment='top',
       bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.9),
       family='monospace')

plt.tight_layout()
plt.savefig(OUTPUT_DIR / 'TradingView_vs_R系统_交易间隔对比.png', dpi=300, bbox_inches='tight')
print("已保存: outputs/TradingView_vs_R系统_交易间隔对比.png")
plt.close()

print("\n所有可视化图表已生成!")

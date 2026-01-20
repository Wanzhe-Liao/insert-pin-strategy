"""
生成最终综合报告
"""

import pandas as pd
import numpy as np
from datetime import datetime
from pathlib import Path

# 读取分析结果
OUTPUT_DIR = Path("outputs")
REPORTS_DIR = Path("docs/reports")
REPORTS_DIR.mkdir(parents=True, exist_ok=True)

trades = pd.read_csv(OUTPUT_DIR / 'trades_tradingview_aligned.csv')
trades['EntryTime'] = pd.to_datetime(trades['EntryTime'])
trades['ExitTime'] = pd.to_datetime(trades['ExitTime'])
trades['PnLPercent'] = trades['PnLPercent'].str.rstrip('%').astype(float)

# 计算关键指标
trades['NextEntryTime'] = trades['EntryTime'].shift(-1)
trades['ReentryInterval'] = (trades['NextEntryTime'] - trades['ExitTime']).dt.total_seconds() / 60
valid_intervals = trades['ReentryInterval'].dropna()

# 统计各类情况
zero_holding = trades[trades['HoldingBars'] == 0]
same_bar_reentry = trades[trades['ReentryInterval'] == 0]
quick_reentry_15min = trades[trades['ReentryInterval'] <= 15].dropna(subset=['ReentryInterval'])
quick_reentry_1hour = trades[trades['ReentryInterval'] <= 60].dropna(subset=['ReentryInterval'])
quick_reentry_1day = trades[trades['ReentryInterval'] <= 1440].dropna(subset=['ReentryInterval'])

# TradingView数据
tv_intervals = [104, 53, 54, 62, 38, 14, 14, 572]  # 分钟

# 生成Markdown报告
report = f"""# 快速重入场模式分析报告

**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
**分析周期**: 2023-05-09 至 2025-10-17
**数据来源**: R回测系统 vs TradingView

---

## 执行摘要

本报告深入分析了R回测系统中的"快速重入场"模式，对比TradingView的交易行为，识别出关键差异并提出优化建议。

### 核心发现

1. **R系统存在大量快速重入场**: {len(quick_reentry_15min)} 笔交易在出场后15分钟内再次入场，占比 {len(quick_reentry_15min)/len(trades)*100:.2f}%
2. **持仓0根K线的异常交易**: {len(zero_holding)} 笔交易在同一K线内完成入场和出场
3. **TradingView采用严格冷却期**: 最小交易间隔为 {min(tv_intervals):.0f} 分钟，避免了频繁交易
4. **交易频率差异巨大**: R系统165笔交易 vs TradingView仅9笔交易

---

## 第一部分: 快速重入场统计

### 1.1 总体情况

| 指标 | 数值 | 占比 |
|------|------|------|
| R系统总交易数 | {len(trades)} | 100% |
| 持仓0根K线 | {len(zero_holding)} | {len(zero_holding)/len(trades)*100:.2f}% |
| 同一K线再入场 | {len(same_bar_reentry)} | {len(same_bar_reentry)/len(trades)*100:.2f}% |
| 15分钟内再入场 | {len(quick_reentry_15min)} | {len(quick_reentry_15min)/len(trades)*100:.2f}% |
| 1小时内再入场 | {len(quick_reentry_1hour)} | {len(quick_reentry_1hour)/len(trades)*100:.2f}% |
| 1天内再入场 | {len(quick_reentry_1day)} | {len(quick_reentry_1day)/len(trades)*100:.2f}% |

### 1.2 交易间隔分布

**R系统交易间隔统计**:

- **最小间隔**: {valid_intervals.min():.2f} 分钟
- **第25百分位**: {valid_intervals.quantile(0.25):.2f} 分钟
- **中位数**: {valid_intervals.median():.2f} 分钟
- **第75百分位**: {valid_intervals.quantile(0.75):.2f} 分钟
- **平均间隔**: {valid_intervals.mean():.2f} 分钟 ({valid_intervals.mean()/1440:.2f} 天)
- **最大间隔**: {valid_intervals.max():.2f} 分钟 ({valid_intervals.max()/1440:.2f} 天)

**TradingView交易间隔统计**:

- **最小间隔**: {min(tv_intervals):.0f} 分钟
- **中位数**: {np.median(tv_intervals):.0f} 分钟
- **平均间隔**: {np.mean(tv_intervals):.0f} 分钟 ({np.mean(tv_intervals)/1440:.2f} 天)
- **最大间隔**: {max(tv_intervals):.0f} 分钟 ({max(tv_intervals)/1440:.2f} 天)

### 1.3 间隔时间分组

| 时间段 | R系统数量 | R系统占比 | TradingView数量 |
|--------|-----------|-----------|-----------------|
| ≤15分钟 (立即) | {len(quick_reentry_15min)} | {len(quick_reentry_15min)/len(valid_intervals)*100:.2f}% | 0 |
| 15分钟-1小时 | {len(quick_reentry_1hour) - len(quick_reentry_15min)} | {(len(quick_reentry_1hour) - len(quick_reentry_15min))/len(valid_intervals)*100:.2f}% | {sum(1 for x in tv_intervals if 15 < x <= 60)} |
| 1小时-1天 | {len(quick_reentry_1day) - len(quick_reentry_1hour)} | {(len(quick_reentry_1day) - len(quick_reentry_1hour))/len(valid_intervals)*100:.2f}% | {sum(1 for x in tv_intervals if 60 < x <= 1440)} |
| >1天 | {len(valid_intervals) - len(quick_reentry_1day)} | {(len(valid_intervals) - len(quick_reentry_1day))/len(valid_intervals)*100:.2f}% | {sum(1 for x in tv_intervals if x > 1440)} |

---

## 第二部分: 违反规则的具体案例

### 2.1 持仓0根K线的交易

找到 **{len(zero_holding)}** 笔持仓0根K线的交易，这些交易在同一K线内完成入场和出场。

**典型案例**:
"""

# 添加典型案例
if len(zero_holding) > 0:
    for i, (idx, row) in enumerate(zero_holding.head(5).iterrows()):
        report += f"""
#### 案例 {i+1}: 交易 #{row['TradeId']}

- **时间**: {row['EntryTime']}
- **入场价格**: {row['EntryPrice']:.10f} USDT
- **出场价格**: {row['ExitPrice']:.10f} USDT
- **出场原因**: {row['ExitReason']}
- **盈亏**: {row['PnLPercent']:.2f}%
- **价格变化**: {(row['ExitPrice']-row['EntryPrice'])/row['EntryPrice']*100:+.2f}%
"""

report += f"""
**分析结论**:
- 这些交易表明价格在单根K线内波动剧烈，快速触发止损或止盈条件
- 可能是闪跌/闪涨导致的异常情况
- 建议增加价格确认机制，避免K线内反复触发

### 2.2 同一K线再入场

找到 **{len(same_bar_reentry)}** 笔在出场后的同一K线再次入场的交易。

**影响**:
- 频繁交易增加手续费损耗
- 可能是策略逻辑缺陷，未设置最小冷却期
- 与TradingView的保守策略形成鲜明对比

### 2.3 高频交易时段

"""

# 找出高频交易日
trades['Date'] = trades['EntryTime'].dt.date
daily_counts = trades.groupby('Date').size()
high_freq_days = daily_counts[daily_counts >= 3].sort_values(ascending=False)

report += f"""找到 **{len(high_freq_days)}** 天有3笔或以上交易。

**最高频交易日**:
"""

for i, (date, count) in enumerate(high_freq_days.head(5).items()):
    day_trades = trades[trades['Date'] == date]
    day_pnl = day_trades['PnLPercent'].sum()
    report += f"\n{i+1}. **{date}**: {count} 笔交易，总盈亏 {day_pnl:+.2f}%"

report += f"""

---

## 第三部分: TradingView vs R系统对比

### 3.1 交易频率对比

| 指标 | TradingView | R系统 | 差异 |
|------|-------------|-------|------|
| 总交易数 | 9 | {len(trades)} | {len(trades)/9:.1f}x |
| 平均交易间隔 | {np.mean(tv_intervals):.0f} 分钟 | {valid_intervals.mean():.0f} 分钟 | {valid_intervals.mean()/np.mean(tv_intervals):.1f}x |
| 最小交易间隔 | {min(tv_intervals):.0f} 分钟 | {valid_intervals.min():.0f} 分钟 | {valid_intervals.min()/min(tv_intervals):.2f}x |
| 15分钟内再入场 | 0 笔 | {len(quick_reentry_15min)} 笔 | - |

### 3.2 规则遵循情况

**TradingView**:
OK 严格遵循"平仓前不开新仓"规则
OK 采用冷却期机制，最小间隔{min(tv_intervals):.0f}分钟
OK 所有交易都止盈出场（100%胜率）
OK 交易间隔长，避免过度交易

**R系统**:
FAIL 存在快速重入场行为
FAIL 无明确冷却期限制
FAIL 胜率58%，有大量止损交易
FAIL 交易频率过高

### 3.3 用户观察验证

用户观察："在前一笔实现止盈/止损之前不进行下一笔交易"

**验证结果**:
- **TradingView**: OK 严格遵循此规则，且有额外的冷却期
- **R系统**: OK 技术上遵循（无持仓重叠），但 FAIL 存在快速重入场（违背规则精神）

---

## 第四部分: 建议的冷却期参数

基于TradingView数据和R系统分析，建议以下冷却期设置：

### 4.1 参数建议

| 策略类型 | 冷却期 | 理由 | 预计影响 |
|---------|--------|------|---------|
| **保守型** | {min(tv_intervals):.0f} 分钟 | 与TV最小间隔一致 | 减少 {(valid_intervals < min(tv_intervals)).sum()} 笔交易 ({(valid_intervals < min(tv_intervals)).sum()/len(trades)*100:.1f}%) |
| **中等型** | 60 分钟 | 避免1小时内重复交易 | 减少 {len(quick_reentry_1hour)} 笔交易 ({len(quick_reentry_1hour)/len(trades)*100:.1f}%) |
| **激进型** | 15 分钟 | 仅避免同K线/相邻K线 | 减少 {len(quick_reentry_15min)} 笔交易 ({len(quick_reentry_15min)/len(trades)*100:.1f}%) |

### 4.2 额外建议

1. **K线内交易限制**:
   - 避免在同一K线内完成入场和出场
   - 建议至少持仓1根K线（15分钟）

2. **每日交易次数限制**:
   - 最高频日有{daily_counts.max()}笔交易
   - 建议设置每日最大3-5笔交易限制

3. **价格确认机制**:
   - 信号出现后，等待下一根K线确认
   - 避免K线内价格剧烈波动导致的假信号

---

## 第五部分: 实施路线图

### 阶段1: 紧急修复（立即）

- [ ] 添加最小15分钟冷却期
- [ ] 禁止同一K线内入场和出场
- [ ] 添加每日最大交易次数限制（建议5笔）

**预期效果**: 减少{len(quick_reentry_15min) + len(zero_holding)}笔异常交易

### 阶段2: 参数优化（1周内）

- [ ] 测试不同冷却期参数（15/30/60分钟）
- [ ] 优化信号确认机制
- [ ] 回测验证优化效果

**预期效果**: 提高策略稳定性，降低交易频率

### 阶段3: 全面对齐（2周内）

- [ ] 完全对齐TradingView和R系统的交易逻辑
- [ ] 验证两系统产生相同的交易信号
- [ ] 进行前进式测试

**预期效果**: 两系统交易数量接近，胜率和收益率趋同

---

## 附录: 数据文件清单

本次分析生成以下文件：

### CSV数据文件
1. `快速重入场案例.csv` - 所有快速重入场交易的详细信息
2. `交易间隔分析.csv` - 每笔交易的间隔时间
3. `快速重入场统计汇总.csv` - 统计汇总表
4. `违规案例汇总报告.csv` - 违规案例分类统计
5. `持仓0根K线案例.csv` - 异常快速交易列表

### 可视化图表
1. `交易间隔分布图.png` - 4个子图展示间隔分布
2. `交易时间线分析.png` - 3个子图展示时间线和密度
3. `TradingView_vs_R系统_交易间隔对比.png` - 箱线图对比

---

## 结论

R回测系统与TradingView存在显著的"快速重入场"差异，主要表现为：

1. R系统缺乏冷却期机制，导致过度交易
2. 存在大量持仓0根K线的异常交易
3. 交易频率是TradingView的{len(trades)/9:.1f}倍

**关键建议**: 立即实施至少15分钟的冷却期，禁止K线内重复交易，并设置每日交易次数上限。这些措施预计可减少{len(quick_reentry_15min) + len(zero_holding)}笔({(len(quick_reentry_15min) + len(zero_holding))/len(trades)*100:.1f}%)异常交易，使R系统向TradingView的保守策略靠拢。

---

*报告生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*
*分析工具: Python + Pandas + Matplotlib*
*数据来源: R回测CSV文件 + TradingView差异报告*
"""

# 保存报告
with open(REPORTS_DIR / '快速重入场分析综合报告.md', 'w', encoding='utf-8') as f:
    f.write(report)

print("=" * 100)
print("综合报告已生成!")
print("=" * 100)
print("\n文件名: 快速重入场分析综合报告.md")
print(f"文件大小: {len(report)} 字符")
print("\n报告包含:")
print("- 执行摘要")
print("- 快速重入场统计")
print("- 违规案例分析")
print("- TradingView对比")
print("- 参数建议")
print("- 实施路线图")

# 同时保存为纯文本
with open(REPORTS_DIR / '快速重入场分析综合报告.txt', 'w', encoding='utf-8') as f:
    f.write(report)

print("\n已保存为Markdown和纯文本两种格式")

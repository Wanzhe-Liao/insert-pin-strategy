# Architecture

## Overview

- What problem it solves:
  - 用 R 实现可控、可重复的策略回测，并尽量 **对齐 TradingView / Pine Script 的行为**，用于策略验证、参数优化与 Walk-Forward 评估。
- Key constraints:
  - 对齐性：信号生成、入场/出场判定、TP/SL 触发与执行价尽量与 TradingView 一致
  - 可解释性：输出交易明细、忽略信号日志、性能统计，便于定位差异
  - 性能：大量参数搜索时需要较快的回测执行（例如滚动窗口最高值用 `RcppRoll`）
- Non-goals:
  - 目前不是一个标准 R package（更多是研究型脚本集合）
  - 不处理交易所真实下单与实盘执行

## Modules & Boundaries

- Core domain (策略/回测核心):
  - `backtest_tradingview_aligned.R`：核心回测引擎与辅助函数（信号、撮合、统计）
- Optimization (参数搜索/打分):
  - `optimization/` 下脚本：对多个交易对/周期或单币种进行并行/智能采样优化，输出最佳参数与报告
  - `run_complete_optimization*.R`：更偏“入口脚本”，串起引擎与优化流程
- Walk-Forward (滚动/扩展窗口验证):
  - `walk_forward_*.R` 与 `walkforward/`、`*_walkforward/` 输出：训练/测试切片后的表现统计
- Comparison/Verification (对齐验证与问题定位):
  - `test_*.R`：脚本式测试与对齐验证
  - 大量 `*.md/*.txt`：对齐、费用模型、差异根因等报告
- Python analysis (少量辅助分析):
  - `run_full_analysis.py` 串起 `analyze_reentry_pattern.py` 等脚本，生成 CSV/PNG

## Key Flows

### Flow 1: 单次回测（R）

1. `load("data/liaochu.RData")` 得到 `cryptodata[["<SYMBOL>_<TF>"]]`（xts）
2. `backtest_tradingview_aligned()`：
   - 生成买入信号（窗口最高价 vs 当前最低价跌幅）
   - 按 K 线迭代，进行持仓状态管理
   - 默认使用 High/Low 判定 TP/SL 触发，并以精确 TP/SL 作为成交价（`exitMode="tradingview"`）
3. 输出交易列表、性能汇总、调试信息（按脚本实现而定）

### Flow 2: 参数优化（R）

1. 选择数据集（多交易对/周期或单一数据集）
2. 在参数空间内采样/搜索（可能并行）
3. 对每组参数调用回测引擎，计算目标函数（收益/回撤/胜率/交易数等权重）
4. 输出最佳参数 CSV 与总结报告

## Data & Config

- Config sources:
  - 目前以脚本内参数为主，部分脚本/文档存在绝对路径（后续整理将统一为相对路径/项目根目录）
- Storage:
  - 主要是本地文件：`.RData`、`*.csv`、`*.md`、`*.txt`、`*.png`

## Build/Test/Deploy

- Build: 无（脚本式工作区）
- Test:
  - 以 `test_*.R` 为主（可用 `Rscript` 运行）
- Deploy: 无

## Risks & TODOs

- Risk:
  - 目录整理时，脚本中的硬编码路径（`source(...)`, `load(...)`, `read.csv(...)`）容易断裂
- TODO:
  - 增加统一的项目根目录定位与路径工具（R/Python）
  - 将“可复用核心”与“一次性实验脚本/报告输出”分层隔离

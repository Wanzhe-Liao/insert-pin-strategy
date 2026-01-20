# Project Map

一句话：这是一个用于 **加密货币策略（如“三日暴跌接针”）** 的回测/对齐/优化/Walk-Forward/对比验证的研究工作区（R 为主，少量 Python）。

## Quick Start

- Prereqs:
  - R `>= 4.4`（已在本机使用 `Rscript 4.4.2` 验证）
  - Python `>= 3.9`（用于少量分析脚本）
- Data:
  - `data/liaochu.RData`：核心数据源文件，加载后通常得到 `cryptodata`（按交易对与周期组织的 xts 数据）
- Run (最常用):
  - 回测引擎：`source("backtest_tradingview_aligned.R")`
  - 优化：`source("run_complete_optimization_parallel.R")` 或 `source("optimization/parallel_smart_search.R")`
  - Walk-Forward：查看 `walkforward/` 与 `*_walkforward/` 输出，或运行 `walk_forward_*.R`
  - Python 分析汇总：`python run_full_analysis.py`
- Test (脚本式测试):
  - `Rscript test_tradingview_alignment.R`
  - `Rscript test_fee_correctness.R`

## Entrypoints

- Backtest engine (R): `backtest_tradingview_aligned.R`
- Optimization (R): `run_complete_optimization_parallel.R`, `optimization/test_all_timeframes.R`, `optimization/parallel_smart_search.R`
- Walk-Forward results: `walkforward/`, `bnb_walkforward/`, `xrp_walkforward/` 等
- Data catalog: `data_catalog/数据源总目录.md`
- Python analysis: `run_full_analysis.py`
- Curated deliverable snapshot: `策略回测汇总_2025-10-27/README.md`

## Directory Guide

| Path | Purpose | Key files | Notes |
|------|---------|-----------|-------|
| `docs/` | 项目文档与报告归档 | `PROJECT_MAP.md`, `ARCHITECTURE.md` | 旧的报告/说明类文档集中在 `docs/guides/` 与 `docs/reports/` |
| `data/` | 数据输入 | `liaochu.RData`, `tradingview_trades.csv` | 统一从这里加载数据 |
| `outputs/` | 运行产出（CSV/PNG 等） | `*.csv`, `*.png` | 脚本默认读写此目录（逐步统一中） |
| `r/engine/` | 可复用核心（回测引擎） | `backtest_tradingview_aligned.R` | 根目录同名文件为兼容 wrapper |
| `r/scripts/` | 研究/一次性脚本 | `compare/`, `debug/`, `optimize/` | 按主题分子目录 |
| `r/tests/` | 脚本式测试 | `test_*.R` | 根目录同名文件为兼容 wrapper |
| `python/scripts/` | Python 分析脚本 | `analyze_reentry_pattern.py` 等 | 由 `run_full_analysis.py` 串联运行 |
| `data_catalog/` | 数据集目录与统计 | `datasets_info.csv`, `数据源总目录.md` | 描述 `data/liaochu.RData` 中的数据覆盖范围 |
| `optimization/` | 优化脚本与输出 | `parallel_smart_search.R`, `test_all_timeframes.R` | 包含安装依赖脚本 `install_packages.R` |
| `walkforward/` | Walk-Forward 输出与报告 | `*_details.csv`, `*_summary.txt` | 主要是结果文件 |
| `*_walkforward/` | 单币种 Walk-Forward 运行与输出 | `*_walk_forward.R` | 例：`bnb_walkforward/` |
| `策略回测汇总_2025-10-27/` | 已整理的策略交付包 | `README.md` | 包含引擎/优化脚本/TradingView 代码 |

## “Where should I put…?”

- 新的可复用回测/策略逻辑：`r/engine/`
- 新的临时分析脚本：`r/scripts/`
- 新的文档/报告：`docs/`
- 新的数据输入/样例：`data/`
- 新的运行产出（CSV/PNG 等）：`outputs/`

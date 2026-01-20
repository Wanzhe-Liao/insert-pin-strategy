# Restructure Plan

## Goals

- Readability goal: 根目录只保留“入口 + 总览”，把脚本/数据/报告按语义归档，做到“新同学 3 分钟能找到入口”。
- Maintainability goal: 将“可复用核心（回测引擎）”与“一次性分析脚本/产出物”分离，减少相互污染与路径硬编码。
- Constraints:
  - 不改变策略/回测逻辑，仅做目录调整与路径修复
  - 逐批迁移、每批可验证
  - 当前目录非 git 仓库：将先做轻量代码备份（不拷贝大数据）

## Target Structure (proposal)

（先整理 2-3 层深度；后续可再细分）

```
/
├─ README.md
├─ docs/
│  ├─ PROJECT_MAP.md
│  ├─ ARCHITECTURE.md
│  ├─ RESTRUCTURE_PLAN.md
│  └─ reports/                 # 归档 *.md/*.txt 报告（非代码）
├─ r/
│  ├─ engine/                  # backtest_* 核心回测引擎与可复用函数
│  ├─ tests/                   # test_*.R 脚本式测试
│  └─ scripts/                 # analyze_*/debug_*/compare_* 等一次性脚本
├─ python/
│  └─ scripts/                 # run_full_analysis.py 等 Python 分析脚本
├─ data/                       # 输入数据（如 liaochu.RData）
├─ outputs/                    # CSV/图片等运行产出（可按主题再分子目录）
├─ optimization/               # 现有优化目录（保留，后续再合并到 r/）
├─ walkforward/                # 现有 walk-forward 输出（保留）
├─ *_walkforward/              # 单币种 walk-forward（后续考虑并入 walkforward/）
└─ 策略回测汇总_2025-10-27/     # 已整理的策略交付包（保留）
```

## Migration Steps (small batches)

1. Step 1 (safe, reversible): 建立目录 + 文档归档
   - Changes:
     - 新增 `docs/reports/`、`r/`、`python/`、`data/`、`outputs/`
     - 将根目录大量报告类 `*.md/*.txt` 迁移到 `docs/reports/`
     - 更新入口文档（`README.md`、`docs/PROJECT_MAP.md`）中的关键链接
   - Validation:
     - 确认关键入口文档可打开且链接不指向不存在的路径

2. Step 2: 回测引擎归位 + 修复 source/load 路径
   - Changes:
     - 将核心引擎 `backtest_*.R` 迁移到 `r/engine/`
     - 全局替换硬编码绝对路径（`...`）为相对路径
   - Validation:
     - `Rscript r/tests/test_tradingview_alignment.R`（或等价入口）能运行到关键函数加载阶段

3. Step 3: 脚本与测试归档
   - Changes:
     - `test_*.R` → `r/tests/`
     - `analyze_*/debug_*/compare_*/check_*/find_*/read_*` → `r/scripts/`
     - Python 脚本 → `python/scripts/`
   - Validation:
     - 运行 1-2 个代表性脚本（R + Python），确保相对路径与输出目录正常

4. Step 4 (optional): Walk-forward 目录归一
   - Changes:
     - `bnb_walkforward/`、`xrp_walkforward/` 等并入 `walkforward/<symbol>/`
   - Validation:
     - 确认所有结果文件仍可在 `walkforward/` 下按币种查找

## Compatibility & Rollback

- Compatibility strategy:
  - 入口脚本统一要求“从项目根目录运行”（`cd 插针` 后再 `Rscript ...` / `python ...`）。
  - 如遇外部依赖固定引用旧路径，将为少数关键入口保留同名 wrapper（仅 `source()` 新位置）。
- Rollback plan:
  - 迁移前做“代码/文档轻量备份”（仅 `*.R/*.py/*.md/*.txt`），需要回滚时可按清单覆盖恢复。

## Risks

- Import/path changes: R 的 `source()`/`load()` 以及文档内的绝对路径需要统一修复。
- Build/CI path changes: 当前无 CI，但脚本入口路径会变化，需要在 `README.md` 中明确。
- Docs link changes: 报告类文档迁移后，互相引用可能断链（优先保证入口文档正确）。


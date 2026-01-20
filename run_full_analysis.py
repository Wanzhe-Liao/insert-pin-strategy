"""
完整快速重入场分析主脚本
运行所有分析模块并生成综合报告
"""

import subprocess
import sys
import os

print("=" * 100)
print("快速重入场模式完整分析")
print("=" * 100)

# 脚本列表
scripts = [
    ("analyze_reentry_pattern.py", "快速重入场统计分析"),
    ("violation_cases_analysis.py", "违规案例详细分析"),
    ("visualize_intervals.py", "可视化图表生成"),
    ("generate_final_report.py", "生成最终综合报告"),
]

results = {}

# 运行所有分析脚本
for script, description in scripts:
    script_path = os.path.join("python", "scripts", script)
    print(f"\n{'='*100}")
    print(f"运行: {description}")
    print(f"脚本: {script_path}")
    print(f"{'='*100}\n")

    try:
        env = os.environ.copy()
        env["PYTHONUTF8"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"

        result = subprocess.run(
            [sys.executable, "-X", "utf8", script_path],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,  # 5分钟超时
            env=env,
        )

        print(result.stdout)

        if result.stderr:
            print(f"\n警告/错误信息:\n{result.stderr}")

        results[script] = {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr
        }

        if result.returncode == 0:
            print(f"\n[OK] {description} 完成")
        else:
            print(f"\n[FAIL] {description} 失败 (返回码: {result.returncode})")

    except subprocess.TimeoutExpired:
        print(f"\n[FAIL] {description} 超时")
        results[script] = {'success': False, 'error': 'timeout'}
    except Exception as e:
        print(f"\n[FAIL] {description} 出错: {str(e)}")
        results[script] = {'success': False, 'error': str(e)}

# 生成执行摘要
print("\n" + "=" * 100)
print("执行摘要")
print("=" * 100)

success_count = sum(1 for r in results.values() if r.get('success', False))
total_count = len(scripts)

print(f"\n总计: {success_count}/{total_count} 个脚本成功运行\n")

for script, result in results.items():
    status = "[OK] 成功" if result.get('success', False) else "[FAIL] 失败"
    print(f"{status} - {script}")

# 检查生成的文件
print("\n" + "=" * 100)
print("生成的文件清单")
print("=" * 100)

expected_files = [
    # CSV文件
    os.path.join("outputs", "快速重入场案例.csv"),
    os.path.join("outputs", "交易间隔分析.csv"),
    os.path.join("outputs", "快速重入场统计汇总.csv"),
    os.path.join("outputs", "违规案例汇总报告.csv"),
    os.path.join("outputs", "持仓0根K线案例.csv"),

    # 图片文件
    os.path.join("outputs", "交易间隔分布图.png"),
    os.path.join("outputs", "交易时间线分析.png"),
    os.path.join("outputs", "TradingView_vs_R系统_交易间隔对比.png"),

    # 报告文件
    os.path.join("docs", "reports", "快速重入场分析综合报告.md"),
    os.path.join("docs", "reports", "快速重入场分析综合报告.txt"),
]

print("\nCSV数据文件:")
for file in expected_files:
    if file.endswith('.csv'):
        exists = os.path.exists(file)
        status = "[OK]" if exists else "[MISSING]"
        size = f"{os.path.getsize(file) / 1024:.1f} KB" if exists else "不存在"
        print(f"  {status} {file} ({size})")

print("\n可视化图表:")
for file in expected_files:
    if file.endswith('.png'):
        exists = os.path.exists(file)
        status = "[OK]" if exists else "[MISSING]"
        size = f"{os.path.getsize(file) / 1024:.1f} KB" if exists else "不存在"
        print(f"  {status} {file} ({size})")

print("\n报告文件:")
for file in expected_files:
    if file.endswith('.md') or file.endswith('.txt'):
        exists = os.path.exists(file)
        status = "[OK]" if exists else "[MISSING]"
        size = f"{os.path.getsize(file) / 1024:.1f} KB" if exists else "不存在"
        print(f"  {status} {file} ({size})")

print("\n" + "=" * 100)
print("完整分析已完成!")
print("=" * 100)

print("\n下一步建议:")
print("1. 查看 '快速重入场统计汇总.csv' 了解整体情况")
print("2. 查看 '违规案例汇总报告.csv' 了解具体问题")
print("3. 打开可视化图表查看交易模式")
print("4. 根据分析结果调整策略参数（冷却期、最大交易频率等）")

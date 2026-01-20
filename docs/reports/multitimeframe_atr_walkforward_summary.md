# Multi-timeframe ATR Walk-Forward Summary

- symbols: DOGEUSDT, PEPEUSDT, XRPUSDT
- timeframes: 5m, 15m, 30m, 1h
- train/test: 12/1 months, last_windows(default)=12
- signalMode: `atr` (atrLength=14)
- search: lookback[2,20], dropATR[2.00,10.00], TP%[0.10,3.00], SL%[5.00,25.00]

## Results (ranked by cumulative OOS return within each symbol)

### DOGEUSDT

- 15m: OOS -41.84%, maxDD -71.04%, Sharpe -0.02, windows 12
- 1h: OOS -55.43%, maxDD -55.43%, Sharpe -1.51, windows 12
- 30m: OOS -62.26%, maxDD -72.39%, Sharpe -1.00, windows 12
- 5m: OOS -65.17%, maxDD -38.70%, Sharpe -1.67, windows 9

### PEPEUSDT

- 1h: OOS -13.46%, maxDD -61.03%, Sharpe 0.29, windows 12
- 5m: OOS -18.24%, maxDD -6.71%, Sharpe 0.12, windows 9
- 15m: OOS -76.60%, maxDD -85.69%, Sharpe -0.93, windows 12
- 30m: OOS -78.94%, maxDD -81.64%, Sharpe -1.62, windows 12

### XRPUSDT

- 30m: OOS 21.03%, maxDD -44.48%, Sharpe 0.58, windows 12
- 1h: OOS -12.84%, maxDD -39.36%, Sharpe -0.20, windows 12
- 15m: OOS -25.54%, maxDD -52.25%, Sharpe -0.22, windows 12
- 5m: OOS -26.88%, maxDD -17.45%, Sharpe -0.43, windows 9

Summary CSV: `docs/reports/multitimeframe_atr_walkforward_summary.csv`

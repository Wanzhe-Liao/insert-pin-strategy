# Multi-timeframe ATR Walk-Forward Summary

- symbols: DOGEUSDT, PEPEUSDT, XRPUSDT
- timeframes: 5m, 15m, 30m, 1h
- train/test: 12/1 months, last_windows(default)=12
- signalMode: `atr` (atrLength=14)
- search: lookback[2,20], dropATR[4.00,12.00], TP%[1.00,8.00], SL%[1.00,6.00]

## Results (ranked by cumulative OOS return within each symbol)

### DOGEUSDT

- 30m: OOS -4.56%, maxDD -39.76%, Sharpe 0.15, windows 12
- 1h: OOS -31.51%, maxDD -32.80%, Sharpe -1.71, windows 12
- 5m: OOS -39.00%, maxDD -5.54%, Sharpe -0.93, windows 9
- 15m: OOS -69.27%, maxDD -69.55%, Sharpe -1.66, windows 12

### PEPEUSDT

- 15m: OOS -21.47%, maxDD -70.12%, Sharpe 0.38, windows 12
- 30m: OOS -29.54%, maxDD -54.41%, Sharpe -0.45, windows 12
- 1h: OOS -31.22%, maxDD -43.58%, Sharpe -1.00, windows 12
- 5m: OOS -47.73%, maxDD -42.55%, Sharpe -0.50, windows 9

### XRPUSDT

- 30m: OOS 6.73%, maxDD -42.18%, Sharpe 0.36, windows 12
- 15m: OOS -2.43%, maxDD -35.05%, Sharpe 0.13, windows 12
- 5m: OOS -22.41%, maxDD -10.80%, Sharpe -0.23, windows 9
- 1h: OOS -23.20%, maxDD -35.63%, Sharpe -0.75, windows 12

Summary CSV: `docs/reports/multitimeframe_atr_walkforward_summary.csv`

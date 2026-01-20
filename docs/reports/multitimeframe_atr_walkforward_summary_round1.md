# Multi-timeframe ATR Walk-Forward Summary

- symbols: DOGEUSDT, PEPEUSDT, XRPUSDT
- timeframes: 5m, 15m, 30m, 1h
- train/test: 12/1 months, last_windows(default)=12
- signalMode: `atr` (atrLength=14)
- search: lookback[2,20], dropATR[4.00,12.00], TP%[1.00,8.00], SL%[1.00,6.00]

## Results (ranked by cumulative OOS return within each symbol)

### DOGEUSDT

- 1h: OOS -41.60%, maxDD -46.76%, Sharpe -2.19, windows 12
- 30m: OOS -52.72%, maxDD -55.66%, Sharpe -2.02, windows 12
- 5m: OOS -62.30%, maxDD -39.40%, Sharpe -1.99, windows 9
- 15m: OOS -77.66%, maxDD -76.53%, Sharpe -3.04, windows 12

### PEPEUSDT

- 1h: OOS -22.31%, maxDD -38.97%, Sharpe -0.61, windows 12
- 5m: OOS -32.71%, maxDD -24.58%, Sharpe -0.21, windows 9
- 30m: OOS -56.33%, maxDD -65.93%, Sharpe -0.90, windows 12
- 15m: OOS -86.11%, maxDD -86.39%, Sharpe -3.06, windows 12

### XRPUSDT

- 30m: OOS -23.07%, maxDD -27.89%, Sharpe -1.43, windows 12
- 15m: OOS -27.41%, maxDD -39.14%, Sharpe -0.68, windows 12
- 1h: OOS -38.85%, maxDD -46.62%, Sharpe -1.64, windows 12
- 5m: OOS -47.29%, maxDD -24.39%, Sharpe -0.83, windows 9

Summary CSV: `docs/reports/multitimeframe_atr_walkforward_summary_round1.csv`

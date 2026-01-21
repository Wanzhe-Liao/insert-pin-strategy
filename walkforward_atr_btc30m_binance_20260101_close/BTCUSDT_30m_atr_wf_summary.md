# ATR Walk-Forward Summary — BTCUSDT_30m

- signalMode: `atr` (atrLength=14)
- exitMode: `close`
- windows: 12 (train=12 months, test=1 months, last_windows=12)
- cumulative out-of-sample return: -32.06%
- max drawdown (OS equity curve): -28.47%
- avg monthly return: -2.85% (sd 8.12%), Sharpe~-1.22
- OS months: +6 / -5 / 0=1

## Parameter stability

- lookback: mean=15.75 sd=4.31
- dropATR:  mean=4.73 sd=1.10
- TP%:     mean=4.06 sd=3.61
- SL%:     mean=4.54 sd=4.21

Details CSV: `walkforward_atr_btc30m_binance_20260101_close/BTCUSDT_30m_atr_wf_details.csv`

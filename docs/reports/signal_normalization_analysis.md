# Signal Normalization Analysis (absolute vs ATR-normalized)

This report explains one common reason for signal scarcity: **volatility regime change**. If the strategy uses a fixed `drop%` threshold (e.g., 10%), then signals will naturally collapse when the market becomes less volatile.

We compare:

- **Absolute drop%**: `(highestHigh - low) / highestHigh * 100 >= minDropPercent`
- **ATR-normalized drop**: `(highestHigh - low) / ATR >= thresholdATR` (threshold is calibrated to match the baseline signal count on the training period)

Notes:

- ATR-normalization changes the meaning of the signal: it detects *relative extremes* under the current volatility regime.
- If your goal is specifically to trade only very large absolute crashes, then signal scarcity is expected and not a bug.

## Results

### BTCUSDT_30m

- Baseline params: lookback=10 bars, drop>=10.50%, TP=1.20%, SL=18.80%
- ATR config: atrLength=14, calibrated thresholdATR=6.8760
- Signals/month (recent last-12 vs earlier): abs 0.17 vs 4.03; atr 4.25 vs 4.03
- TradeCount (abs vs atr): 129 vs 120
- Monthly CSV: `outputs/signal_normalization_monthly_BTCUSDT_30m.csv`

### BNBUSDT_15m

- Baseline params: lookback=10 bars, drop>=10.70%, TP=0.40%, SL=12.70%
- ATR config: atrLength=14, calibrated thresholdATR=6.4552
- Signals/month (recent last-12 vs earlier): abs 1.25 vs 9.63; atr 9.50 vs 9.63
- TradeCount (abs vs atr): 334 vs 399
- Monthly CSV: `outputs/signal_normalization_monthly_BNBUSDT_15m.csv`


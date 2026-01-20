# Trade Decline Diagnosis (Recent months vs earlier years)

This report decomposes the observed decline in trade openings into signal frequency vs holding/locking effects.

## Key conclusion

- In the checked datasets/params, the dominant driver is **signal scarcity** (monthly signal counts collapse in recent months), not a sudden increase in holding time.

## Details

### BTCUSDT_30m

- Params: lookback=10 bars, drop>=10.50%, TP=1.20%, SL=18.80%
- Recent (last 12 months in data): avg signals/month=0.17, avg trades/month=0.17
- Earlier: avg signals/month=4.03, avg trades/month=1.46
- Holding time proxy (avg holding bars on months with trades): recent=1.00, earlier=171.56
- Drop% max (proxy for regime volatility): recent max=14.61, earlier max=36.60
- Monthly metrics CSV: `outputs/trade_decline_monthly_metrics_BTCUSDT_30m.csv`

### BNBUSDT_15m

- Params: lookback=10 bars, drop>=10.70%, TP=0.40%, SL=12.70%
- Recent (last 12 months in data): avg signals/month=1.25, avg trades/month=0.25
- Earlier: avg signals/month=9.63, avg trades/month=3.94
- Holding time proxy (avg holding bars on months with trades): recent=5.33, earlier=50.35
- Drop% max (proxy for regime volatility): recent max=31.03, earlier max=39.88
- Monthly metrics CSV: `outputs/trade_decline_monthly_metrics_BNBUSDT_15m.csv`

### PEPEUSDT_15m

- Params: lookback=8 bars, drop>=7.00%, TP=1.40%, SL=12.80%
- Recent (last 12 months in data): avg signals/month=34.83, avg trades/month=9.17
- Earlier: avg signals/month=70.39, avg trades/month=20.00
- Holding time proxy (avg holding bars on months with trades): recent=104.85, earlier=43.93
- Drop% max (proxy for regime volatility): recent max=67.75, earlier max=28.44
- Monthly metrics CSV: `outputs/trade_decline_monthly_metrics_PEPEUSDT_15m.csv`


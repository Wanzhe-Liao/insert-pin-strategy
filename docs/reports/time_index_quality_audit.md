# Time Index Quality Audit

This report audits the time index of `cryptodata` (loaded from `data/liaochu.RData`).

- Total datasets: 75
- Datasets with non-increasing steps (diff<=0): 0
- Datasets with near-zero steps (|diff|<0.5s): 12
- Datasets with step mismatch vs expected (by name suffix): 51

## Worst gaps (Top 20 by max gap seconds)

| dataset | tf | bars | max_gap_s | non_inc | near_zero | step_gt_expected |
|---|---:|---:|---:|---:|---:|---:|
| BTCUSDT_1h | 1h | 71701 | 124305.211 | 0 | 1 | 31 |
| ETHUSDT_1h | 1h | 71701 | 124305.200 | 0 | 1 | 31 |
| BNBUSDT_1h | 1h | 69764 | 124304.213 | 0 | 0 | 30 |
| BTCUSDT_30m | 30m | 143382 | 122505.211 | 0 | 1 | 33 |
| ETHUSDT_30m | 30m | 143382 | 122505.200 | 0 | 1 | 33 |
| BNBUSDT_30m | 30m | 139508 | 122504.213 | 0 | 0 | 32 |
| BTCUSDT_15m | 15m | 286748 | 121605.211 | 0 | 1 | 34 |
| ETHUSDT_15m | 15m | 286748 | 121605.200 | 0 | 1 | 34 |
| BNBUSDT_15m | 15m | 279000 | 121604.213 | 0 | 0 | 33 |
| BTCUSDT_5m | 5m | 860222 | 121005.211 | 0 | 1 | 35 |
| ETHUSDT_5m | 5m | 860222 | 121005.200 | 0 | 1 | 35 |
| BNBUSDT_5m | 5m | 836979 | 121004.213 | 0 | 0 | 34 |
| LTCUSDT_5m | 5m | 826335 | 121003.188 | 0 | 0 | 33 |
| BTCUSDT_3m | 3m | 1433693 | 120885.211 | 0 | 1 | 36 |
| ETHUSDT_3m | 3m | 1433693 | 120885.200 | 0 | 1 | 36 |
| BNBUSDT_3m | 3m | 1394954 | 120884.213 | 0 | 0 | 35 |
| BTCUSDT_1m | 1m | 4301049 | 120765.211 | 0 | 1 | 36 |
| ETHUSDT_1m | 1m | 4301049 | 120765.200 | 0 | 1 | 36 |
| BNBUSDT_1m | 1m | 4184834 | 120764.213 | 0 | 0 | 35 |
| FETUSDT_1h | 1h | 58323 | 39600.000 | 0 | 0 | 22 |

# Market Curve LOVE20 Pricing Design

## Goal

让 market-curve 对任意计价代币统一使用 LOVE20 作为价格中间层，并减少首屏请求与重复计算，降低页面加载时间。

## Pricing Invariant

- `LOVE20 / quote` 使用 LOVE20 与当前计价代币的交易对。
- `token / quote` 对所有非 LOVE20 代币统一计算为：`token / LOVE20 * LOVE20 / quote`。
- 当 `quote=LOVE20` 时，直接使用 `token / LOVE20`。
- 即使 token 存在直连 quote 交易对，也忽略该直连价格。
- 若缺少所需交易对，返回该代币的明确不可绘制原因，不回退到直连交易对。

## Data Flow

1. 服务端解析已知代币和当前 quote，定位 LOVE20。
2. 当 quote 不是 LOVE20 时，一次查询并生成 `LOVE20 / quote` 的 bridge candles。
3. 对每个非 LOVE20 代币查询 `token / LOVE20` candles；当 quote 是 LOVE20 时直接使用该 candles，否则将两组 candles 按时间戳合并。
4. 合并时对每个时间点使用不晚于该时间的最新两组 close 值；只有两组价格都存在时才生成结果，价格为两者相乘。
5. 派生 candle 的 `close_block` 取两组最新样本区块的较大值，继续用目标 token 的铸造/销毁事件计算市值。
6. 页面直接请求完整数据。完整响应已经包含 tokens、quote 和 series，因此移除初始串行的 `meta=1` 请求。

## Performance Boundaries

- `LOVE20 / quote` 的 pair 查找、Sync 查询和 candle 聚合在一次数据请求内只执行一次，所有 token series 复用结果。
- 不引入跨请求缓存，避免活库更新后的陈旧数据。
- 保留现有数据库索引和显式 `tokens` 参数兼容行为。
- 不改变前端的图例显隐和指标切换；切换指标继续只重绘，不重新查询。

## Error Handling

- quote 不存在时保持现有 `quote token not found` 错误。
- quote 不是 LOVE20 且缺少 LOVE20/quote 交易对时，所有需要桥接的 token series 返回 bridge pair 缺失原因；LOVE20 series 本身仍返回该缺失原因。
- token/LOVE20 缺失时，仅该 token series 返回交易对缺失原因。
- 两组 candles 没有可对齐的有效历史价格时，该 token 返回无数据状态，不伪造价格。

## Verification

- 单元测试验证间接价格乘法、时间点以前值的延续、`quote=LOVE20` 直接路径，以及存在直连 quote 时仍忽略直连价格。
- 性能回归验证初次页面只发一个完整数据请求，并验证 bridge candles 不按 token 重复查询。
- 保持现有页面契约、完整 Python 测试和 JS 语法检查通过。

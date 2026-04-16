# DB Dashboards

`script/log/dashboards/` 用来存放基于 `script/log/db/*.db` 的单页面分析看板。

约定：

- 每个看板单独一个子目录。
- 子目录内至少包含：
  - `index.html`：当前单页。
- 看板默认展示 `log_round` 口径；`log_round` 是按区块推导出的协议轮次，不等同于事件 payload 里的 `round` 字段。
- 页面默认通过本地 `dashboard_server.py` 查询活 `events.db`。
- 浏览器只负责展示与手动查询，SQL 与时间线归并都在服务端执行。
- 服务端直接查询活库，不做过期缓存。

当前看板：

- `mint-addresses-by-log-round/`
  展示每一轮有铸币地址数、治理铸币地址数、行动铸币地址数。
  默认隐藏最新同步到的进行中轮次，可在页面中手动切换显示。
  现在由服务端直接查询活 `events.db` 并缓存结果；SQL 来源于 `source_query.sql` 与 `source_summary.sql`。

- `wallet-activity-timeline/`
  输入钱包地址后，按区块和交易顺序展示该地址的时间线。
  页面支持输入每页 tx 数，默认 100。服务端会一次返回最近 N 笔交易的交易级摘要、原始交易数据、以及该 tx 下全部原始事件。
  页面会把 `ClaimReward`、`groupJoin`、`Approval`、`groupVerify.SubmitOriginScores`、转账、加池 / LP 铸造等动作归并成交易级摘要表格；默认每条对应单笔交易，未命中已识别事件模式的调用也会保留，并可在前端直接展开原始 tx / events。
  现在由服务端按地址实时聚合活 `events.db`，并按页加载更早记录。

使用说明：

```bash
cd /Users/BigPolarBear/Documents/github/LOVE20TKM/script/script/log/dashboards
python3 dashboard_server.py --host 127.0.0.1 --port 8000 --network thinkium70001_public
```

然后先访问统一入口页：

- `http://127.0.0.1:8000/dashboards/`

入口页会列出当前看板，并可点击后新开 tab 打开具体看板。

也可直接访问具体看板：

- `http://127.0.0.1:8000/dashboards/mint-addresses-by-log-round/`
- `http://127.0.0.1:8000/dashboards/wallet-activity-timeline/`

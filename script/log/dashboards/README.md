# DB Dashboards

`script/log/dashboards/` 用来存放基于 `script/log/db/*.db` 的单页面分析看板。

约定：

- 每个看板单独一个子目录。
- 子目录内至少包含：
  - `query.sql`：看板主查询。
  - `index.html`：当前单页。
- 看板默认展示 `log_round` 口径；`log_round` 是按区块推导出的协议轮次，不等同于事件 payload 里的 `round` 字段。
- 页面默认直接读取看板专用 SQLite，例如 `mint-addresses-by-log-round/data/thinkium70001_public.db`。
- SQLite 查询在浏览器内执行，依赖仓库内置的 `vendor/sql.js/`。

当前看板：

- `mint-addresses-by-log-round/`
  展示每一轮有铸币地址数、治理铸币地址数、行动铸币地址数。
  默认隐藏最新同步到的进行中轮次，可在页面中手动切换显示。
  原始 `events.db` 太大时，先通过 shell 脚本从源库提炼出看板专用 SQLite，再由页面直接查询。

使用说明：

```bash
cd /Users/BigPolarBear/Documents/github/LOVE20TKM/script/script/log
./dashboards/mint-addresses-by-log-round/refresh.sh thinkium70001_public
python3 -m http.server 8000
```

然后访问：

- `http://127.0.0.1:8000/dashboards/mint-addresses-by-log-round/`

如果不想起本地静态服务，页面也支持手动选择本地看板 SQLite 文件。

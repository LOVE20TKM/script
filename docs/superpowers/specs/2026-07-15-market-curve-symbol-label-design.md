# Market Curve Symbol Label Design

## Goal

让 market-curve 的曲线悬停提示显示代币 symbol，而不是用于内部标识的合约地址。

## Design

- 保留 `tokenKey(item)`：继续优先使用合约地址，确保图例显隐、曲线图层和交互定位不会因 symbol 重名而冲突。
- 生成曲线悬停点时，除内部 `token` 键外，同时保存 `item.token.symbol` 作为显示名称；仅在 symbol 缺失时回退到内部键。
- 悬停提示读取显示名称，不再直接显示内部键。
- 不修改服务端接口、代币发现逻辑、图例内容或其它 dashboard。

## Verification

- 页面契约测试确认悬停点携带 symbol，悬停文本使用该 symbol。
- 运行 market-curve 页面测试，确认内部地址键与现有交互契约保持不变。

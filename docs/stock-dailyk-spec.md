# 行业“异常买入/疑似建仓”检测算法（分钟K + 行业聚合）

目标：用分钟级量价协同，识别某个行业在某天是否出现“异常主动买入倾向”（更像资金在行业层面配置/建仓），并输出：
- **信号强度**：`Z_rel`（行业相对全市场的异常程度）
- **结构确认**：`breadth`（行业内有多少成份股同向偏买）
- **可信度**：`Q`（过滤器合成质量分）

---

## 1. 输入数据

### 1.1 分钟K（每只股票、每个交易日）
对每只股票 `s`、交易日 `d`，有分钟序列 `t ∈ T(d)`（按时间升序）：

- `close[s,t]` 分钟收盘价（必须）
- `volume[s,t]` 分钟成交量（必须）
- `amount[s,t]` 分钟成交额（可选，但建议有；若无，可把相关过滤器关掉或用日成交量代替）

### 1.2 行业成份股集合
对每个行业 `I`，当天成份股集合：
- `S_I(d)`：行业 `I` 在交易日 `d` 的成份股列表

### 1.3 全市场股票池
用于计算市场基准（相对强弱）：
- `S_M(d)`：交易日 `d` 的市场股票池（建议用你有分钟数据的全部可交易股票）

### 1.4 交易日列表
- `days = [d1, d2, ... , dK]` 升序（你现在有过去20天）

---

## 2. 核心思想与指标定义

### 2.1 分钟“方向函数”（软方向推荐）
对股票 `s` 在分钟 `t`，定义分钟收益：
- `r[s,t] = ln(close[s,t] / close[s,t-1])`

定义软方向（避免“假红假绿”）：
- `phi(r) = tanh(r / tau)`，输出范围 `(-1, 1)`
- `tau` 是灵敏度参数（常用 0.0005 ~ 0.0015，需回测调参）

### 2.2 分钟压力（Signed Volume）
- `p[s,t] = volume[s,t] * phi(r[s,t])`

直观解释：  
- 价格上行且幅度大 → `phi>0` → 压力为正  
- 价格下行且幅度大 → `phi<0` → 压力为负  
- 小波动 → `phi≈0` → 贡献很小

### 2.3 单股日内“归一化压力”
对股票 `s` 在日 `d`：
- `P_sum[s,d] = Σ_t p[s,t]`
- `V_sum[s,d] = Σ_t volume[s,t]`

归一化（消除大票成交量优势）：
- `X_hat[s,d] = P_sum[s,d] / (V_sum[s,d] + delta)`
- `delta` 很小的常数防止除0（如 1e-9）

`X_hat` 大致在 `[-1, 1]`，代表该股当日“主动买入倾向”。

---

## 3. Hard Filters（股票级硬过滤，先剔除脏数据/极端结构）

对每只股票日内特征再做过滤，防止分钟统计被“少数异常分钟/缺数据/无流动性”劫持。

### F1 流动性过滤（可选，推荐用成交额）
- `A_sum[s,d] = Σ_t amount[s,t]`
- 若 `A_sum[s,d] < minDailyAmount` → 剔除  
  - `minDailyAmount` 例：2000万~5000万 RMB（按你的池子调整）

若没有 `amount`：可关闭此过滤器，或用 `V_sum` 的阈值替代。

### F2 分钟覆盖率过滤（推荐）
- 设 `expectedMinutes`：应有分钟数
  - A股连续竞价通常可取 240（不含集合竞价）
- 覆盖率：`coverage = minuteCount / expectedMinutes`
- 若 `coverage < minMinuteCoverage` → 剔除（如 0.9）

### F3 单分钟成交量脉冲过滤（推荐）
避免“一根异常分钟”主导方向统计：
- `maxV = max_t volume[s,t]`
- `maxShare = maxV / (V_sum[s,d] + delta)`
- 若 `maxShare > maxMinuteVolShare` → 剔除（如 0.08~0.15）

---

## 4. 行业聚合（Industry-level aggregation）

对行业 `I` 在日 `d`：

### 4.1 通过过滤的成份股集合
- `S_I_pass(d) = { s ∈ S_I(d) | s 通过 Hard Filters }`

### 4.2 权重（推荐：成交额权重 + 封顶）
先计算日成交额权重（或日成交量权重）：
- `w_raw[s] = A_sum[s,d] / Σ_{k∈S_I_pass} A_sum[k,d]`

做权重封顶（避免龙头票统治）：
- `w_cap[s] = min(w_raw[s], w_max)`，如 `w_max = 0.08`

再归一化：
- `w[s] = w_cap[s] / Σ w_cap`

若没有 `amount`：可用等权，或用 `V_sum` 替代。

### 4.3 行业压力值（当日）
- `X_I[d] = Σ_{s∈S_I_pass} w[s] * X_hat[s,d]`

---

## 5. 全市场基准（Market baseline）

用同样的方法，计算市场池 `S_M(d)` 的当日压力：
- 对 `S_M(d)` 中所有通过过滤的股票，取 `X_hat[s,d]` 的平均或加权平均

推荐简单版本（均值即可）：
- `X_M[d] = mean_{s∈S_M_pass(d)} X_hat[s,d]`

---

## 6. 行业相对强度（去大盘伪信号）

定义相对值：
- `X_rel[I,d] = X_I[d] - X_M[d]`
（beta=1 的版本足够好用；精细版可回归估计 beta）

解释：  
- 若行业只是跟随大盘情绪，上下同涨同跌 → `X_rel` 不会异常  
- 若资金在行业层面“超额配置” → `X_rel` 显著为正

---

## 7. 异常度（Rolling Z-score）

对每个行业 `I`，在滚动窗口 `W`（建议 20，或你仅有20天就用20）内做标准化：

- `mu = mean(X_rel[I, d-W+1 ... d])`
- `sigma = std(X_rel[I, d-W+1 ... d])`
- `Z_rel[I,d] = (X_rel[I,d] - mu) / (sigma + epsSigma)`

`epsSigma` 如 1e-9。

---

## 8. 结构确认指标（Breadth）

行业广度（通过过滤的成份股中，有多少是“偏买”的）：
- `breadth[I,d] = count( X_hat[s,d] > 0 ) / |S_I_pass(d)|`

解释：
- `Z_rel` 高但 breadth 低 → 可能是少数龙头驱动，不一定是行业建仓
- `Z_rel` 高且 breadth 高 → 更像行业层面一致性买入

---

## 9. 可信度评分（Quality score Q）

输出一个 `Q ∈ [0,1]`，把过滤器与结构特征合成，避免策略“被噪音骗”。

建议用乘法合成（简单有效）：

### 9.1 覆盖率分
- `passedCount = |S_I_pass(d)|`
- `Q_coverage = min(1, passedCount / minPassedMembers)`  
  - `minPassedMembers` 例：8（行业太小信号不稳定）

### 9.2 广度分
线性映射：
- `Q_breadth = clip01( (breadth - breadthLow) / (breadthHigh - breadthLow) )`
  - `breadthLow=0.30, breadthHigh=0.55` 例

### 9.3 集中度惩罚（HHI）
计算权重集中度：
- `HHI = Σ w[s]^2`

惩罚函数：
- `Q_conc = exp( -lambda * max(0, HHI - HHI0) )`
  - `HHI0` 例：0.06
  - `lambda` 例：12

### 9.4 持续性（可选但推荐）
建仓通常不是“一天行情”，加一个软判定：
- `persistOk = 最近 L 天中，Z_rel > persistZ 的天数 >= persistNeed`
  - 如 `L=5, persistZ=1.0, persistNeed=3`

映射：
- `Q_persist = 1.0 if persistOk else 0.6`

### 9.5 合成
- `Q = clip01( Q_coverage * Q_breadth * Q_conc * Q_persist )`

---

## 10. 最终输出与“异常建仓”判定建议

每个行业 `I`、每个交易日 `d` 输出：

- `Z_rel[I,d]`：行业相对异常买入强度（主信号）
- `breadth[I,d]`：行业内一致性
- `Q[I,d]`：可信度
- 以及诊断信息：`passedCount / memberCount`, `X_I[d]`, `X_M[d]`

### 建议判定阈值（需回测）
一个可用的初始规则：
- `Z_rel > 1.5`
- `Q > 0.6`
- `breadth > 0.35`

然后按 `Z_rel` 从高到低排序，作为“疑似行业建仓候选”。

---

## 11. 参数建议（起步默认）

- `tau = 0.001`
- `W(zWindow) = 20`
- `minDailyAmount = 2e7`（若有 amount）
- `minMinuteCoverage = 0.90`（若 expectedMinutes=240）
- `maxMinuteVolShare = 0.12`
- 权重：`amountCapped`，`w_max = 0.08`
- `breadthLow = 0.30`, `breadthHigh = 0.55`
- `minPassedMembers = 8`
- `HHI0 = 0.06`, `lambda = 12`
- 持续性：`L=5, persistZ=1.0, persistNeed=3`

---

## 12. 实现注意事项

1) `days` 必须严格升序，rolling z 才正确。  
2) 分钟数据要按时间升序，且相邻分钟 close 才能算 `r`。  
3) A股建议把 `expectedMinutes = 240` 写死（否则覆盖率过滤无意义）。  
4) `amount` 如果缺失：
   - 关闭 `minDailyAmount` 过滤器
   - 权重用等权或用 `V_sum` 替代
   - 但集中度(HHI)仍可用等权/量权计算
5) 过滤器阈值会显著影响结果：建议先用默认值跑通，再做回测网格调参。

---

## 13. 复杂度与缓存建议（20天分钟数据）

- 先对每只股票每个交易日计算 `X_hat` 和日内统计（V_sum、A_sum、maxShare、minuteCount）
- 行业聚合与市场基准只用这些日级特征，避免重复扫分钟K
- 这样整体复杂度从 `O(行业×股票×分钟)` 降为：
  - 预处理：`O(股票×分钟)`
  - 聚合：`O(行业×股票)`



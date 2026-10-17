---
title: Groq Whisper、Gemini Flash-Lite 與 Antigravity CLI（agy）潤稿的可行性
createdAt: 2026-10-16
---

# Groq Whisper、Gemini Flash-Lite 與 Antigravity CLI（agy）潤稿的可行性

查詢日期 2026-10-16，價格與模型清單都以這天的官方頁面為準

## 一、Groq whisper-large-v3-turbo

### 現況與價格

Groq 目前只上架兩個語音辨識模型，文件沒有任何下架公告 [1]

| 模型 | 價格（每小時音訊） | 官方速度倍率 | 官方 WER | 翻譯 |
| --- | --- | --- | --- | --- |
| whisper-large-v3-turbo | $0.04 | 216 倍即時 | 12% | 不支援 |
| whisper-large-v3 | $0.111 | 189 倍即時 | 10.3% | 支援 |

- 沒有更便宜或更快的選項，distil-whisper 已不在模型清單，rate limit 頁也只列這兩個 [1][2]
- turbo 本身就是最便宜也最快的那個，代價是 WER 略高
- distil-whisper 原本就只支援英文，就算還在也不適合中文
- 中文：官方只說兩者都是多語模型，建議帶 ISO-639-1 語言碼（`language=zh`）以提升準確度與速度 [1]
- 參考我們前一份研究的表，Whisper-large-v3 在 CommonVoice zh-TW 的 MER 是 10.17，中英夾雜（ASCEND）19.61，遠差於 TEA-ASR 1.1 的 3.58 與 9.60，turbo 只會更差一點，而且輸出常是簡體，需要靠 prompt 或後處理轉繁體 [5]

### 額度

- rate limit 頁列出的 Whisper 基礎額度是 20 RPM、每天 2K 次、每小時 7.2K 秒音訊、每天 28.8K 秒音訊，但頁面標示這是 Developer plan 的基礎額度，免費方案實際數字要到帳號的 limits 頁看 [2]
- 以聽寫用途來說，每天 8 小時音訊上限遠超過個人用量

### 能不能直接接上現有的 API 語音來源

可以，路徑完全相容 OpenAI [1]

- Base URL：`https://api.groq.com/openai/v1`
- 端點：`POST /audio/transcriptions`，multipart 上傳，`model=whisper-large-v3-turbo`，回傳 JSON 帶 `text`
- 驗證：`Authorization: Bearer <GROQ_API_KEY>`

### 延遲估算

官方只給速度倍率，沒有給端到端延遲。216 倍即時代表一段 5 秒音訊在伺服器上只要約 25 毫秒，實際體感主要是上傳音檔加網路來回，台灣連美國機房大約落在 0.3 到 0.8 秒（推估，未實測）

## 二、Gemini Flash-Lite

### 目前有哪些 Flash-Lite

| 模型 | 狀態 | 輸入／輸出（每 1M tokens） | 免費額度 | 預設思考 |
| --- | --- | --- | --- | --- |
| gemini-3.5-flash-lite | Stable | $0.30 / $2.50 | 有 | 開，minimal |
| gemini-3.1-flash-lite | Stable | $0.25 / $1.50 | 有 | 頁面沒有獨立一列 |
| gemini-2.5-flash-lite | 仍提供，限曾經用過的帳號 | $0.10 / $0.40 | 有 | 關 |

來源 [3][4][6]

- 2.5 Flash-Lite 已經被 3.1 與 3.5 Flash-Lite 取代，模型頁說 2.5 系列沒有被棄用、會繼續提供，但只開放給以前用過的使用者，新帳號可能選不到 [4]
- 最便宜的文字模型仍是 2.5 Flash-Lite，Batch 更便宜（$0.05 / $0.20）但要付費方案，而且不適合即時聽寫 [3]
- 定價頁另列 Gemma 4 在免費層免費，但沒有付費價格 [3]
- 一句潤稿約 300 tokens 進、50 tokens 出，3.5 Flash-Lite 每句約 $0.0002，2.5 Flash-Lite 約 $0.00005

### OpenAI 相容端點

可以接上現有的 API 文字來源 [6]

- Base URL：`https://generativelanguage.googleapis.com/v1beta/openai/`
- 端點：`POST chat/completions`
- 驗證：`Authorization: Bearer <GEMINI_API_KEY>`

### 思考預算的坑

- `reasoning_effort` 對 3.x Flash-Lite 對應到 `thinking_level`，`minimal` 對應 minimal [6]
- `reasoning_effort: "none"` 只對 2.5 系列有效，文件寫 Gemini 3 系列不能完全關掉思考 [6]
- 2.5 Flash-Lite 預設本來就不思考，3.5 Flash-Lite 預設是 minimal [7]
- 結論：用 3.x Flash-Lite 時請送 `reasoning_effort: "minimal"`，最省延遲；用 2.5 Flash-Lite 可送 `"none"` 或乾脆不送

### 延遲

官方頁面沒有公布 TTFT 或每秒 token 數，這次也沒有 API key 可以實測，下表的 API 數字是推估。Flash-Lite 等級的模型在思考關閉或 minimal 時，短句潤稿通常 0.4 到 1 秒可回完整結果，實際上線前要自己量

## 三、AGY 是什麼

`agy` 是 Google Antigravity 的命令列工具，本機已安裝在 `~/.local/bin/agy`，版本 1.3.4

### Gemini CLI 已經不能用個人 Google 登入

本機的 `gemini`（0.53.0）用個人帳號跑 `-p` 時直接回錯誤：

```
IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals.
To continue using Gemini, please migrate to the Antigravity suite of products
```

也就是說，靠 Google 登入免費用 Gemini CLI 這條路已經關掉，個人方案要改用 agy（2026-10-16 本機實測）

### agy 的無介面模式

`agy --help` 顯示的旗標跟 `claude -p` 幾乎一一對應

- `--print`／`-p`：跑一次就印出結果
- `--output-format text|json|stream-json`
- `--input-format stream-json`：從 stdin 一行讀一則 NDJSON，每則跑一輪，必須搭配 `--output-format stream-json`，可以讓同一個行程一直活著，跟我們 Claude 的做法一樣
- `--model`、`--effort low|medium|high|xhigh|max`、`--sandbox`、`--mode plan`、`--disable-slash-commands`
- 注意：`-p` 會把下一個參數當成提示詞，長駐模式要寫成 `--print=` 放在最後
- stream-json 輸入格式跟 Claude 不同，要寫成 `{"event":"user","message":{"content":"..."}}`，結果是 `{"event":"result","result":{"response":"..."}}`（本機實測，官方說明頁未查到）

### 可選模型

`agy models` 在本機列出的清單（依帳號方案可能不同）：

- gemini-4-argon-low／medium／high
- gemini-3.8-flash-low／medium／high
- claude-opus-5-5、claude-sonnet-5-5（各三檔）
- gpt-oss-120b-medium

清單裡沒有任何 Flash-Lite，最輕的是 gemini-3.8-flash-low

### 本機實測

句子：我那個明天要去開meeting然後deadline是禮拜五，要求整理成通順繁中

| 方式 | 模型 | 每句時間 |
| --- | --- | --- |
| 每句開一次 `agy -p` | 預設模型 | 8.8 秒、6.7 秒 |
| 長駐 stream-json，第 1 句 | gemini-3.8-flash-low | 6.2 秒（含啟動） |
| 長駐 stream-json，第 2 到 4 句 | gemini-3.8-flash-low | 3.2、2.4、2.0 秒 |

- 結果正確：我明天要去開會，截止日期是星期五
- 每輪輸入約 13,000 tokens，原因是 agy 會帶上整套 agent 系統提示與工具清單，而且多輪會累積對話，這是慢的主因
- 沒有找到關掉工具或替換系統提示的旗標，`init` 事件仍會列出整套工具

### 條款

這是最大的問題

- Antigravity FAQ 寫明 `agy -p` 是給直接寫腳本與 CI 用，把 agy 包進第三方程式或 App 在消費者方案下不支援 [8]
- 服務條款寫明用第三方軟體存取服務屬違約，可能停用 Antigravity 和 Gemini CLI 帳號 [9]
- 官方論壇 2026 年 9 到 10 月有大量同類提問，問的正是用別的程式呼叫官方 agy 子行程算不算違規，目前沒看到放寬 [10]
- FAQ 沒有列各方案的額度數字，只指向 Plans 頁 [8]

結論：Hyday Talk 用使用者的 Google AI 訂閱透過 agy 潤稿，在條款上站不住，技術上也比 Claude 慢兩倍以上，不建議做

## 四、速度比較

### 語音辨識（約 5 秒一句）

| 方案 | 每句延遲 | 中文品質 | 費用 |
| --- | --- | --- | --- |
| 本機 TEA-ASR／Qwen3-ASR | 約 1 秒（已實測） | 最好，直接輸出繁體 | 免費 |
| Groq whisper-large-v3-turbo | 約 0.3 到 0.8 秒（推估，網路為主） | 明顯較差，常出簡體 | 每小時 $0.04 |

Groq 頂多快幾百毫秒，換來辨識率變差、要上網、要轉繁體，不划算，適合當作沒有 Apple Silicon 或想省電時的備案

### 潤稿（一句）

| 方案 | 每句延遲 | 備註 |
| --- | --- | --- |
| Ollama qwen3.5:9b 熱機 | 約 0.75 秒（已實測） | 本機、免費 |
| Gemini Flash-Lite API | 約 0.4 到 1 秒（推估） | 要 API key，3.x 請送 minimal |
| Claude Haiku 長駐 CLI | 約 0.9 秒（已實測） | 用 Claude 訂閱 |
| agy 長駐 CLI，3.8 Flash low | 2 到 3 秒熱機，首句 6 秒（已實測） | 條款不允許，選不到 Flash-Lite |
| agy 每句重開 | 7 到 9 秒（已實測） | 不可用 |

## 參考資料

1. Groq Docs, Speech to Text, https://console.groq.com/docs/speech-to-text（2026-10-16 讀取）
2. Groq Docs, Rate Limits, https://console.groq.com/docs/rate-limits（2026-10-16 讀取）
3. Gemini API, Pricing, https://ai.google.dev/gemini-api/docs/pricing（2026-10-16 讀取）
4. Gemini API, Models, https://ai.google.dev/gemini-api/docs/models（2026-10-16 讀取）
5. 本專案 docs/research/asr-tea-and-haiku-sdk.md，TEA-ASR 1.1 作者自測表
6. Gemini API, OpenAI compatibility, https://ai.google.dev/gemini-api/docs/openai（2026-10-16 讀取）
7. Gemini API, Thinking, https://ai.google.dev/gemini-api/docs/thinking（2026-10-16 讀取）
8. Google Antigravity Docs, FAQ, https://antigravity.google/docs/faq/（2026-10-16 讀取）
9. Google Antigravity, Terms of Service, https://antigravity.google/terms（2026-10-16 讀取）
10. Google AI Developers Forum, 例如 https://discuss.ai.google.dev/t/clarification-on-consumer-plan-policy-for-invoking-official-agy-via-local-subprocess/189905（2026-10-16）

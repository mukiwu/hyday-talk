---
title: TEA-ASR 1.1 與 Claude Haiku 5.5 經 Claude Code CLI 潤稿的可行性
createdAt: 2026-10-15
---

# TEA-ASR 1.1 與 Claude Haiku 5.5 經 Claude Code CLI 潤稿的可行性

## 一、TEA 1.1 是什麼

使用者說的 TEA 1.1 是 `JacobLinCool/TEA-ASR-1.1`，全名 Taiwan Everyday Audio，作者是 Hugging Face 上的 JacobLinCool [1]

- 底模：`Qwen/Qwen3-ASR-1.7B`，用 decoder LoRA 微調後合併成單一 checkpoint，載入方式跟原版 Qwen3-ASR 完全相同 [1]
- 授權：MIT [1]
- 語言標記：zh、en，主打台灣國語、繁體中文輸出、台灣用詞，以及中英夾雜 [1]
- 繁體與台灣用詞是改寫 tokenizer 做到的，推論時不需要後處理，所以轉檔時一定要帶上 TEA 自己的 tokenizer，不能沿用原版 Qwen3-ASR 的詞表 [1]
- 建議推論時指定 `language="Chinese"`，可避免中英夾雜被翻成英文 [1]
- 官方只發 safetensors，給 `qwen-asr` 套件與 transformers 用，沒有官方 GGUF [1]

### 同系列

| Repo | 底模 | 檔案 | 大小（bytes） |
| --- | --- | --- | --- |
| JacobLinCool/TEA-ASR-1.1 | Qwen3-ASR-1.7B（約 2B） | model.safetensors | 4,076,191,640 |
| JacobLinCool/TEA-ASR-1.1-mini | Qwen3-ASR-0.6B（約 780M） | model.safetensors | 1,564,926,456 |
| JacobLinCool/TEA-ASR-1.1-fmt、-mini-fmt | 同上 | 可切換數字寫法（108年 或 一百零八年），中英夾雜略差 | 未列 |

另有前一代 TEA-ASR-1、TEA-ASR-1-mini [2]

### 作者自測成績（MER，越低越好，比對前先轉簡體）

| 資料集 | TEA-ASR-1.1 | 1.1-mini | Qwen3-ASR-1.7B | Qwen3-ASR-0.6B | Breeze-ASR-25 | Whisper-large-v3 |
| --- | --- | --- | --- | --- | --- | --- |
| CommonVoice 19 zh-TW | 3.58 | 5.12 | 3.90 | 5.79 | 8.03 | 10.17 |
| ASCEND 中英夾雜 | 9.60 | 11.20 | 10.57 | 12.54 | 17.53 | 19.61 |
| CSZS 中英夾雜 | 10.94 | 12.51 | 11.03 | 16.03 | 12.18 | 23.24 |
| NTUML2021 課堂 | 6.67 | 7.53 | 10.12 | 11.03 | 7.50 | 9.68 |

辨識率只比原版 Qwen3-ASR 好一點，真正的差別在於直接輸出繁體與台灣用詞，原版輸出簡體 [1]

## 二、能不能用 whisper.cpp 或 transcribe.cpp 跑

結論：whisper.cpp 不行，transcribe.cpp 目前沒有現成可用的檔案，要自己轉

- whisper.cpp 只吃 Whisper 架構的 GGML，TEA 是 Qwen3-ASR 架構，直接排除
- transcribe.cpp 有支援 Qwen3-ASR 0.6B 與 1.7B，吃的是自家轉換器 `scripts/convert-qwen3_asr.py` 產出的單檔 GGUF，官方預建檔放在 `handy-computer/Qwen3-ASR-*-gguf`，也就是 App 目前用的那兩份 [3][4]
- Hugging Face 上現有的 TEA GGUF 都不是這個格式

| Repo | 格式 | 給 transcribe.cpp 用 |
| --- | --- | --- |
| mradermacher/TEA-ASR-1.1-GGUF | llama.cpp mtmd 拆檔：文字模型一份加 mmproj 音訊塔一份 | 不行，transcribe.cpp 要單檔融合式 |
| dseditor/TEA-ASR-1.1-CrispASR-GGUF | CrispASR 的單檔 qwen3asr 格式，用 CrispASR 轉換器產出 | 未驗證，轉換器與 tensor 命名來自另一個專案，不能假設相容 |
| Alkd/TEA-ASR-1.1-MLX-4bit | MLX | 不行 |

dseditor 的 README 也指出 mradermacher 那份是 llama.cpp 拆檔慣例，CrispASR 都載不進去 [5]

### 現成檔案的 sha256（給之後評估用，目前沒有一份能直接塞進 LocalSpeechModels）

mradermacher/TEA-ASR-1.1-GGUF（llama.cpp 用，要搭配 mmproj）[6]

| 檔名 | bytes | sha256 |
| --- | --- | --- |
| TEA-ASR-1.1.Q4_K_M.gguf | 1107138976 | 815c55c47966191335d8b1bd9d56a9d4582bfe8b998d58c8608be8e359110dbc |
| TEA-ASR-1.1.Q6_K.gguf | 1417484704 | 524fb1ecf59c44295a7f09a5bba08afe53731c1f25c9a9cdcbc87f7e68c84e42 |
| TEA-ASR-1.1.Q8_0.gguf | 1834156448 | 243c56e6cae05c047d42f1c7136cfa3e5b500b86b7d5d7fa44b3ca43cabfe35e |
| TEA-ASR-1.1.mmproj-Q8_0.gguf | 355709856 | 76b4e355d7057b2799a512bebce9a0c1b1309fcd6b580400a7bddc268e4fd40a |
| TEA-ASR-1.1.mmproj-f16.gguf | 641774496 | 9f8401d36c759a65cc96ebbfdc093c468e998d719f5d02168be41f40bf6a480b |

其他量化（IQ4_XS、Q2_K、Q3_K_S/M/L、Q4_K_S、Q5_K_S/M）也在同一個 repo

dseditor/TEA-ASR-1.1-CrispASR-GGUF [7]

| 檔名 | bytes | sha256 |
| --- | --- | --- |
| tea-asr-1.1-q8_0.gguf | 2506458656 | addf14b8e4b80e605b1639f9bbbb2e4052ac90d94f380a9df9896117f41f4153 |

原始權重 [8]

| 檔名 | bytes | sha256 |
| --- | --- | --- |
| TEA-ASR-1.1/model.safetensors | 4076191640 | 1e9db0943be34be1e6d13b9a895dfccfe941de045bba1b502d8449431ee79ea2 |
| TEA-ASR-1.1-mini/model.safetensors | 1564926456 | e47068bb2cab8117f7432f7dad1341f8a4c2d592fcb5b9fb88309c6f36abe7e7 |

### 要接進 App 的路

1. 用 transcribe.cpp 的 `scripts/convert-qwen3_asr.py` 對 `JacobLinCool/TEA-ASR-1.1`（或 mini）轉檔，再量化成 Q8_0 或 Q6_K [4]
2. 確認轉出來的檔案帶的是 TEA 的 tokenizer，實際跑一段台灣口語，看輸出是不是繁體；dseditor 轉 CrispASR 時遇過 `tie_word_embeddings` 放在 `thinker_config.text_config` 底下、轉換器讀不到而漏掉 `output.weight` 的問題，transcribe.cpp 的轉換器可能也會踩到 [5]
3. 自己上傳到一個 Hugging Face repo，取得固定的 filename、bytes、sha256 後再寫進 `LocalSpeechModels.swift`
4. README 目前寫 Qwen3-ASR 採 Apache 2.0，TEA 是 MIT，加進去時授權說明要一起改

mini 版轉 Q8_0 估計約 850 MB，跟現在預設的 Qwen3-ASR 0.6B 差不多，適合當繁中預設

## 三、用 Claude Haiku 5.5 經 Claude Code CLI 潤稿

### 模型

`claude-haiku-5-5` 是正式的 Claude API ID 與別名 [9]，CLI 的 `--model` 可接完整名稱或 `haiku` 別名 [10]

### 呼叫方式

headless 模式就是 `claude -p`，Agent SDK 的 CLI 形式 [11]，潤稿用的最小呼叫：

```bash
claude -p \
  --model claude-haiku-5-5 \
  --tools "" \
  --system-prompt "把使用者的口述整理成通順的繁體中文，只輸出結果" \
  --setting-sources "" \
  --strict-mcp-config \
  --no-session-persistence \
  --output-format json \
  "<轉錄文字>"
```

- `--tools ""` 關掉所有內建工具 [10]；`--disallowedTools "*"` 也能把所有工具移出 context [10]
- `--system-prompt` 或 `--system-prompt-file` 整個取代預設 system prompt；`--append-system-prompt` 則是保留 Claude Code 預設行為再附加，潤稿不需要預設行為，用取代的 [10][11]
- `--output-format json` 回傳一個 JSON，文字在 `result`，另有 `is_error`、`session_id`、`total_cost_usd`、`duration_ms` 等欄位 [11]；要串流就用 `stream-json` 加 `--verbose --include-partial-messages` [11]
- 轉錄文字可以從 stdin 餵進去，上限 10MB [11]，比放在參數裡安全，不用處理跳脫
- 失敗時 exit code 非 0，但驗證失敗這類執行中的錯誤會印在 stdout 的 result 裡，所以要看 `is_error` [11]
- `--no-session-persistence` 不把每次潤稿存成 session，避免使用者的 `~/.claude` 堆滿紀錄 [10]

### 為什麼不能用 --bare

文件建議腳本呼叫加 `--bare` 加速啟動，但 bare 模式完全不讀 OAuth 與 keychain，只能用 `ANTHROPIC_API_KEY` [11]，跟用訂閱登入的需求衝突。替代做法是用 `--setting-sources ""` 加 `--strict-mcp-config` 擋掉使用者設定與 MCP，並在一個空的工作目錄執行，避免讀到別的專案的 `.claude/settings.json`、`.mcp.json` 與 CLAUDE.md；不加 bare 時，`-p` 在沒信任過的資料夾也會執行該專案的 hooks 與 MCP [11]

注意 `--setting-sources ""` 只管 user、project、local 設定，使用者家目錄的 CLAUDE.md 與 auto memory 是否仍載入，文件沒寫清楚，因為用了 `--system-prompt` 取代整段 prompt，實測沒有看到影響，但上線前建議再確認

### 驗證與條款

- 使用者需自己裝 Claude Code，並在終端機跑過 `claude` 用自己的 Pro 或 Max 帳號登入，App 只呼叫未修改的官方執行檔，不碰 token
- 法遵頁寫明 OAuth 是給訂閱者一般使用 Claude Code 與 Anthropic 原生應用程式；開發者做產品、包括用 Agent SDK 的，應該用 API key；不允許第三方在自己的 App 提供 Claude.ai 登入，或代使用者經 Free、Pro、Max 憑證轉送請求，也不能收集、儲存或中介 Claude.ai 憑證 [12]
- 同一段也寫，這不妨礙終端使用者用自己的訂閱登入未修改的 Claude Code 執行檔 [12]
- Pro、Max 的額度是以一般個人使用 Claude Code 與 Agent SDK 為前提 [12]

判讀：Hyday Talk 呼叫使用者自己已登入的 `claude` CLI，介於兩段之間，屬於灰色地帶。比較穩的做法是在設定頁把它做成使用者自己選的選項，標明會用到他自己的 Claude 訂閱額度，App 不內建登入流程、不讀憑證；若要對外散布當主打功能，建議先問 Anthropic 業務窗口，或改走 API key（APIClient 已經有這條路）

### 延遲

本機實測兩次（Claude Code 2.1.300，上面那組參數，一句短口述）

| 項目 | 第一次 | 第二次 |
| --- | --- | --- |
| 整個行程 wall time | 2.90 秒 | 2.91 秒 |
| CLI 回報 duration_ms | 1466 | 1402 |
| time_to_request_ms（啟動到送出請求） | 565 | 354 |

每次都要啟動一個 Node 行程，固定多出約 1.5 秒，比直接打 API 慢；想縮短可以改成常駐一個 `--input-format stream-json` 的行程重複送訊息，但要自己管行程生命週期。Haiku 5.5 本身預設沒開 extended thinking（回傳的 thinkingTokens 為 0）

### repo 現況

`Sources/` 沒有任何呼叫 `claude` CLI 或 Anthropic 的地方，唯一出現 claude 字樣的是 `Tests/TalkCoreTests/ScreenContextTests.swift` 裡一個視窗標題的測試資料。`CLIExecutableDiscovery.swift` 的搜尋目錄已經包含 `~/.local/bin`，正好是 Claude Code 原生安裝的位置，之後要找 `claude` 執行檔可以沿用，只是 `speechToolNames` 目前只列語音工具

## 資料來源

1. https://huggingface.co/JacobLinCool/TEA-ASR-1.1
2. https://huggingface.co/api/models?search=TEA-ASR
3. https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/qwen3-asr.md
4. https://github.com/handy-computer/transcribe.cpp/blob/main/docs/models/qwen3-asr-1.7b.md
5. https://huggingface.co/dseditor/TEA-ASR-1.1-CrispASR-GGUF
6. https://huggingface.co/api/models/mradermacher/TEA-ASR-1.1-GGUF/tree/main
7. https://huggingface.co/api/models/dseditor/TEA-ASR-1.1-CrispASR-GGUF/tree/main
8. https://huggingface.co/api/models/JacobLinCool/TEA-ASR-1.1/tree/main 與 https://huggingface.co/api/models/JacobLinCool/TEA-ASR-1.1-mini/tree/main
9. https://platform.claude.com/docs/en/about-claude/models/overview
10. https://code.claude.com/docs/en/cli-reference
11. https://code.claude.com/docs/en/headless
12. https://code.claude.com/docs/en/legal-and-compliance

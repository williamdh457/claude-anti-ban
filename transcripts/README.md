# 参考视频字幕

两期参考视频都**没有官方字幕**。这里是用 `whisper.cpp`（`ggml-small` 模型，中文）对音频做 ASR 转写，再人工校对术语后的结果。

| 文件 | 内容 |
|---|---|
| `video-1-claude-stable.md` | 《如何长期稳定使用 Claude 订阅，原理 + 实操的手把手教学》校对稿（含时间轴、章节、本手册补充） |
| `video-2-hyperv.md` | 《为什么我说它是 Windows 平台最好的虚拟机，Hyper-V 虚拟机详细安装教程》校对稿 |
| `raw/video-1.srt` `raw/video-2.srt` | 原始 SRT（带时间戳，未校对） |
| `raw/video-1-asr.txt` `raw/video-2-asr.txt` | 原始 ASR 文本（按 15 秒合并） |

## 复现方法

```bash
# 1. 取音频
yt-dlp -f bestaudio -x --audio-format mp3 -o "vid1.%(ext)s" "https://youtu.be/8lNWd7PvvCU"
ffmpeg -i vid1.mp3 -ar 16000 -ac 1 -c:a pcm_s16le vid1.wav

# 2. 模型（约 466 MB）
curl -L -o ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin

# 3. 转写
whisper-cli -m ggml-small.bin -f vid1.wav -l zh -t 8 -otxt -osrt -of vid1
```

## 常见 ASR 错字对照

| ASR | 实际 |
|---|---|
| Cloud | Claude |
| 实区 | 时区 |
| 公单 | 工单 |
| 手艺 / relaysys | 主页 / Releases |
| vlays | vless |
| KOS 验证 | KYC 验证 |
| 下令 10 | 夏令时 |
| 温石 | Win10 |
| 拖击帐夫 | 脱机账户 |
| 印象文件 | 映像文件 |
| 技术啪啪瞎 | 技术爬爬虾 |
| 位于重谋 | 未雨绸缪 |
| 中端 | 终端 |
| 成文 | 成本 |

> 校对原则：保留原话的意思和顺序，只修术语与明显错字；博主的口语重复做了轻度合并。`〔注〕` 与「本手册补充」是后加的，不属于原视频内容。

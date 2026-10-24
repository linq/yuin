# 本地测试数据

`server.py` 仅绑定本机随机端口，提供生成的静音 WAV、HTTP 回显和源协议测试脚本。

`silence-128.mp3`、`silence-320.mp3`、`silence-16.flac`、`silence-24.flac` 均是 0.5 秒、44.1 kHz、双声道的程序生成静音，用于验证实际编码格式、码率和位深，不含第三方音乐。

生成方式（仅重建文件时需要 FFmpeg，运行测试不需要）：

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.5 -c:a libmp3lame -b:a 128k silence-128.mp3
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.5 -c:a libmp3lame -b:a 320k silence-320.mp3
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.5 -c:a flac -sample_fmt s16 silence-16.flac
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.5 -c:a flac -sample_fmt s32 silence-24.flac
```

`crypto-vectors.json` 用于与 OpenSSL 的 AES/RSA 输出对照。

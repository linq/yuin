# Third-party notices

The LX API compatibility structure and music-platform adapters in `Sources/MusicCore/Catalog.swift` and `Sources/MusicSourceHost/` were independently implemented in Swift/JavaScript with reference to LX Music Desktop 2.12.6 (`/Users/linq/dev/lx-music-desktop`). QQ request-signature constants/algorithm and Migu request parameters are adaptations of its `musicSdk/tx/utils/crypto.js` and `musicSdk/mg/musicSearch.js`. Platform parsing and endpoint parameters reference the corresponding `musicSdk` adapters.

LX Music Desktop by lyswhut ([upstream repository](https://github.com/lyswhut/lx-music-desktop)) is licensed under the Apache License, Version 2.0. A copy is retained in [licenses/LX-Music-Apache-2.0.txt](licenses/LX-Music-Apache-2.0.txt). This application is a separate native implementation, with a separate process for source scripts and native AVPlayer playback; it does not embed the LX application.

The platform lyric request parameters and Kuwo/Kugou lyric decoding in `Sources/MusicCore/Lyrics.swift` reference the corresponding LX `musicSdk/*/lyric.js`, Kuwo `util.js`, and `common/utils/lyricUtils/kg.js` adapters. The LRC parser, native synchronized lyrics presentation and caching are implemented separately in Swift.

Apple system frameworks and the system zlib library are dynamically linked. There are no downloaded Swift package dependencies.

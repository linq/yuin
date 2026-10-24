import CryptoKit
import Foundation

public actor MusicCatalog {
  private let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }
  private func json(
    _ base: String, _ params: [String: String] = [:], body: [String: Any]? = nil,
    referer: String? = nil, headers: [String: String] = [:], qqSign: Bool = false,
    repairUTF8: Bool = false
  ) async throws -> [String: Any] {
    var c = URLComponents(string: base)!
    c.queryItems =
      (c.queryItems ?? [])
      + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    var req = URLRequest(url: c.url!)
    req.timeoutInterval = 20
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    req.setValue(referer ?? base, forHTTPHeaderField: "Referer")
    for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
    if let body {
      req.httpMethod = "POST"
      req.httpBody = try JSONSerialization.data(
        withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if qqSign, let data = req.httpBody {
      let digest = Array(Insecure.SHA1.hash(data: data))
      let hex = Array(digest.map { String(format: "%02x", $0) }.joined())
      func pick(_ indexes: [Int]) -> String {
        String(indexes.compactMap { hex.indices.contains($0) ? hex[$0] : nil })
      }
      let mask: [UInt8] = [
        89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121,
        179,
      ]
      let middle = Data(zip(digest, mask).map { $0 ^ $1 }).base64EncodedString().filter {
        !"/+=\\".contains($0)
      }
      let sign =
        ("zzc" + pick([23, 14, 6, 36, 16, 40, 7, 19]) + middle
        + pick([16, 1, 32, 12, 19, 27, 8, 5])).lowercased()
      c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "sign", value: sign)]
      req.url = c.url
      req.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
    }
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw MusicError.message(
        L10n.text("平台接口请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）"))
    }
    guard data.count <= 30_000_000 else { throw MusicError.message(L10n.text("平台返回数据过大")) }
    // QQ's legacy playlist search occasionally truncates multibyte characters inside text fields.
    let payload = repairUTF8 ? Data(String(decoding: data, as: UTF8.self).utf8) : data
    do { return try Self.decodeObject(payload) } catch {
      throw MusicError.message(L10n.text("平台接口返回格式异常，暂时无法使用"))
    }
  }
  public static func decodeObject(_ data: Data) throws -> [String: Any] {
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      return object
    }
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    let value = try decoder.decode(JSONValue.self, from: data)
    guard
      let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        as? [String: Any]
    else { throw MusicError.message(L10n.text("不是 JSON 对象")) }
    return object
  }
  public func search(_ query: String, platform: MusicPlatform, page: Int = 1) async throws
    -> TrackPage
  {
    let size = 30
    let items: [[String: Any]]
    let total: Int
    switch platform {
    case .kw:
      let d = try await json(
        "https://search.kuwo.cn/r.s",
        [
          "client": "kt", "all": query, "pn": "\(page-1)", "rn": "\(size)", "ft": "music",
          "encoding": "utf8", "rformat": "json", "vipver": "1", "newver": "1", "mobi": "1",
          "vermerge": "1", "show_copyright_off": "1",
        ])
      guard d["TOTAL"] != nil else { throw unavailable(platform) }
      items = d.array("abslist")
      total = d.int("TOTAL")
    case .wy:
      let d = try await json(
        "https://music.163.com/api/search/get",
        ["s": query, "type": "1", "limit": "\(size)", "offset": "\((page-1)*size)"],
        referer: "https://music.163.com/")
      guard d.int("code") == 200, let result = d["result"] as? [String: Any] else {
        throw unavailable(platform)
      }
      items = result.array("songs")
      total = result.int("songCount")
    case .kg:
      let d = try await json(
        "https://songsearch.kugou.com/song_search_v2",
        [
          "platform": "AndroidFilter", "iscorrection": "1", "keyword": query, "hifiquality": "0",
          "pagesize": "\(size)", "PrivilegeFilter": "0", "page": "\(page)",
        ])
      guard d.int("status") == 1 else { throw unavailable(platform) }
      items = d.object("data").array("lists")
      total = d.object("data").int("total")
    case .tx:
      let payload: [String: Any] = [
        "comm": ["ct": "19", "cv": "2151", "uin": "0", "tmeAppID": "qqmusic", "tmeLoginType": 0],
        "req": [
          "module": "music.search.SearchCgiService", "method": "DoSearchForQQMusicDesktop",
          "param": [
            "query": query, "num_per_page": size, "page_num": page, "search_type": 0, "grp": 1,
            "remoteplace": "txt.newclient.top",
            "searchid": UUID().uuidString.replacingOccurrences(of: "-", with: "") + "00000",
          ],
        ],
      ]
      let d = try await json(
        "https://u.y.qq.com/cgi-bin/musics.fcg", body: payload, referer: "https://y.qq.com/",
        qqSign: true)
      let result = d.object("req")
      guard d.int("code") == 0, result.int("code") == 0, !result.isEmpty else {
        throw unavailable(platform)
      }
      let song = result.object("data").object("body").object("song")
      guard song["list"] != nil else { throw unavailable(platform) }
      items = song.array("list")
      total = result.object("data").object("meta").int("sum")
    case .mg:
      let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
      let device = "963B7AA0D21511ED807EE5846EC87D20"
      let sign = Insecure.MD5.hash(
        data: Data(
          (query + "6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50" + device
            + timestamp).utf8)
      ).map { String(format: "%02x", $0) }.joined()
      let d = try await json(
        "https://jadeite.migu.cn/music_search/v3/search/searchAll",
        [
          "text": query, "pageNo": "\(page)", "pageSize": "\(size)",
          "searchSwitch":
            "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":1,\"mvSong\":0,\"bestShow\":1,\"songlist\":0,\"lyricSong\":0}",
          "sid": "USS", "isCopyright": "1", "isCorrect": "0", "sort": "0",
        ], referer: "https://m.music.migu.cn/",
        headers: [
          "uiVersion": "A_music_3.6.1", "deviceId": device, "timestamp": timestamp, "sign": sign,
          "channel": "0146921",
        ])
      let song = d.object("songResultData")
      guard d.string("code") == "000000", !song.isEmpty else { throw unavailable(platform) }
      items = (song["resultList"] as? [[[String: Any]]] ?? []).flatMap { $0 }
      total = song.int("totalCount")
    }
    return TrackPage(
      tracks: Self.unique(items.compactMap { Self.track($0, platform: platform) }), total: total)
  }
  /// Search the platform's online playlist catalogue (not just the loaded recommendations).
  public func searchCollections(_ query: String, platform: MusicPlatform, page: Int = 1)
    async throws -> CollectionPage
  {
    let size = 30
    let rows: [[String: Any]]
    let total: Int
    switch platform {
    case .kw:
      let d = try await json(
        "https://search.kuwo.cn/r.s",
        [
          "all": query, "pn": "\(max(0, page - 1))", "rn": "\(size)", "rformat": "json",
          "encoding": "utf8", "ver": "mbox", "vipver": "MUSIC_8.7.7.0_BCS37",
          "plat": "pc", "devid": "28156413", "ft": "playlist", "pay": "0", "needliveshow": "0",
        ])
      guard d["TOTAL"] != nil else { throw unavailable(platform) }
      rows = d.array("abslist")
      total = d.int("TOTAL")
    case .wy:
      let d = try await json(
        "https://music.163.com/api/search/get",
        [
          "s": query, "type": "1000", "limit": "\(size)", "offset": "\(max(0, page - 1) * size)",
        ], referer: "https://music.163.com/")
      guard d.int("code") == 200, d["result"] != nil else { throw unavailable(platform) }
      rows = d.object("result").array("playlists")
      total = d.object("result").int("playlistCount")
    case .kg:
      let d = try await json(
        "https://msearchretry.kugou.com/api/v3/search/special",
        [
          "keyword": query, "page": "\(max(1, page))", "pagesize": "\(size)",
          "showtype": "10", "filter": "0", "version": "7910", "sver": "2",
        ])
      guard d["errcode"] != nil, d.int("errcode") == 0, d["data"] != nil else {
        throw unavailable(platform)
      }
      rows = d.object("data").array("info")
      total = d.object("data").int("total")
    case .tx:
      let d = try await json(
        "https://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist",
        [
          "query": query, "page_no": "\(max(0, page - 1))", "num_per_page": "\(size)",
          "format": "json", "remoteplace": "txt.yqq.playlist", "inCharset": "utf8",
          "outCharset": "utf-8",
        ], referer: "https://y.qq.com/portal/search.html", repairUTF8: true)
      guard d["code"] != nil, d.int("code") == 0, d["data"] != nil else {
        throw unavailable(platform)
      }
      rows = d.object("data").array("list")
      total = d.object("data").int("sum")
    case .mg:
      let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
      let device = "963B7AA0D21511ED807EE5846EC87D20"
      let sign = Insecure.MD5.hash(
        data: Data(
          (query + "6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50" + device
            + timestamp).utf8)
      ).map { String(format: "%02x", $0) }.joined()
      let d = try await json(
        "https://jadeite.migu.cn/music_search/v3/search/searchAll",
        [
          "text": query, "pageNo": "\(max(1, page))", "pageSize": "\(size)", "isCorrect": "1",
          "isCopyright": "1", "sort": "0", "sid": "USS",
          "searchSwitch":
            "{\"song\":0,\"album\":0,\"singer\":0,\"tagSong\":0,\"mvSong\":0,\"bestShow\":0,\"songlist\":1,\"lyricSong\":0}",
        ], referer: "https://m.music.migu.cn/",
        headers: [
          "uiVersion": "A_music_3.6.1", "deviceId": device, "timestamp": timestamp, "sign": sign,
          "channel": "0146921",
        ])
      guard d["songListResultData"] != nil else { throw unavailable(platform) }
      rows = d.object("songListResultData").array("result")
      total = d.object("songListResultData").int("totalCount")
    }
    var seen = Set<String>()
    let lists: [MusicCollection] = rows.compactMap { row in
      let id: String
      let title: String
      let author: String
      let artwork: String
      switch platform {
      case .kw:
        id = row.string("playlistid")
        title = row.string("name")
        author = row.string("nickname")
        artwork = row.string("pic")
      case .wy:
        id = row.string("id")
        title = row.string("name")
        author = row.object("creator").string("nickname")
        artwork = row.string("coverImgUrl")
      case .kg:
        id = row.string("specialid")
        title = row.string("specialname")
        author = row.string("nickname")
        artwork = row.string("imgurl").replacingOccurrences(of: "{size}", with: "400")
      case .tx:
        id = row.string("dissid")
        title = row.string("dissname")
        author = row.object("creator").string("name")
        artwork = row.string("imgurl")
      case .mg:
        id = row.string("id")
        title = row.string("name")
        author = row.string("userName")
        artwork = row.string("musicListPicUrl")
      }
      guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { return nil }
      return MusicCollection(
        id: id, title: Self.clean(title), subtitle: Self.clean(author), artwork: artwork,
        platform: platform)
    }
    return CollectionPage(collections: lists, total: max(total, lists.count))
  }
  public func collections(platform: MusicPlatform, charts: Bool, page: Int = 1) async throws
    -> [MusicCollection]
  {
    if charts {
      switch platform {
      case .kw:
        return [
          ("93", L10n.text("飙升榜")), ("16", L10n.text("热歌榜")), ("17", L10n.text("新歌榜")),
          ("26", L10n.text("经典怀旧榜")), ("104", L10n.text("华语榜")),
          ("22", L10n.text("欧美榜")),
        ].map {
          MusicCollection(
            id: $0.0, title: $0.1, subtitle: L10n.text("酷我官方榜单"), platform: platform, isChart: true)
        }
      case .wy:
        let d = try await json(
          "https://music.163.com/api/toplist", referer: "https://music.163.com/")
        guard d.int("code") == 200, d["list"] != nil else { throw unavailable(platform) }
        return d.array("list").map {
          MusicCollection(
            id: $0.string("id"), title: $0.string("name"), subtitle: $0.string("updateFrequency"),
            artwork: $0.string("coverImgUrl"), platform: platform, isChart: true)
        }
      case .kg:
        let d = try await json(
          "http://mobilecdnbj.kugou.com/api/v5/rank/list",
          [
            "version": "9108", "plat": "0", "showtype": "2", "parentid": "0", "apiver": "6",
            "area_code": "1", "withsong": "1",
          ])
        guard d.int("status") == 1 else { throw unavailable(platform) }
        return d.object("data").array("info").map {
          MusicCollection(
            id: $0.string("rankid"), title: $0.string("rankname"),
            artwork: $0.string("imgurl").replacingOccurrences(of: "{size}", with: "400"),
            platform: platform, isChart: true)
        }
      case .tx:
        let d = try await json(
          "https://u.y.qq.com/cgi-bin/musicu.fcg",
          body: [
            "req": ["module": "musicToplist.ToplistInfoServer", "method": "GetAll", "param": [:]]
          ], referer: "https://y.qq.com/")
        let r = d.object("req")
        guard r.int("code") == 0, !r.isEmpty else { throw unavailable(platform) }
        return r.object("data").array("group").flatMap { $0.array("toplist") }.map {
          MusicCollection(
            id: $0.string("topId"), title: $0.string("title"), artwork: $0.string("frontPicUrl"),
            platform: platform, isChart: true)
        }
      case .mg:
        let d = try await json(
          "https://app.c.nf.migu.cn/pc/bmw/rank/rank-index/v1.0",
          referer: "https://app.c.nf.migu.cn/", headers: ["channel": "0146921"])
        guard d.string("code") == "000000" else { throw unavailable(platform) }
        func ranks(_ rows: [[String: Any]]) -> [[String: Any]] {
          rows.flatMap { $0["rankId"] != nil ? [$0] : ranks($0.array("contents")) }
        }
        return ranks(d.object("data").array("contents")).map {
          MusicCollection(
            id: $0.string("rankId"), title: $0.string("rankName"), artwork: $0.string("imageUrl"),
            platform: platform, isChart: true)
        }
      }
    }
    switch platform {
    case .kw:
      let d = try await json(
        "https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList",
        [
          "loginUid": "0", "loginSid": "0", "appUid": "76039576", "pn": "\(page)", "rn": "30",
          "order": "hot",
        ])
      guard d.int("code") == 200 else { throw unavailable(platform) }
      return d.object("data").array("data").filter { $0.string("digest") == "8" }.map {
        MusicCollection(
          id: $0.string("id"), title: Self.clean($0.string("name")), subtitle: $0.string("uname"),
          artwork: $0.string("img"), platform: platform)
      }
    case .wy:
      let d = try await json(
        "https://music.163.com/api/playlist/list",
        ["cat": "全部", "order": "hot", "limit": "30", "offset": "\((page-1)*30)"],
        referer: "https://music.163.com/")
      guard d.int("code") == 200 else { throw unavailable(platform) }
      return d.array("playlists").map {
        MusicCollection(
          id: $0.string("id"), title: $0.string("name"),
          subtitle: $0.object("creator").string("nickname"), artwork: $0.string("coverImgUrl"),
          platform: platform)
      }
    case .kg:
      let d = try await json(
        "http://www2.kugou.kugou.com/yueku/v9/special/getSpecial",
        ["is_ajax": "1", "cdn": "cdn", "t": "5", "c": "", "p": "\(page)"])
      guard d.int("status") == 1, d["special_db"] != nil else { throw unavailable(platform) }
      return d.array("special_db").map {
        MusicCollection(
          id: $0.string("specialid"), title: $0.string("specialname"),
          subtitle: $0.string("nickname"),
          artwork: $0.string("img", "imgurl").replacingOccurrences(of: "{size}", with: "400"),
          platform: platform)
      }
    case .tx:
      let payload: [String: Any] = [
        "comm": ["cv": 1602, "ct": 20],
        "req": [
          "module": "music.playlist.PlaylistSquare", "method": "GetRecommendWhole",
          "param": ["IsReqFeed": true, "FeedReq": ["From": (page - 1) * 30, "Size": 30]],
        ],
      ]
      let data = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
      let d = try await json(
        "https://u.y.qq.com/cgi-bin/musicu.fcg", ["data": data], referer: "https://y.qq.com/")
      let r = d.object("req")
      guard r.int("code") == 0, !r.isEmpty else { throw unavailable(platform) }
      return r.object("data").object("FeedRsp").array("List").map { row in
        let x = row.object("Playlist").object("basic")
        return MusicCollection(
          id: x.string("tid"), title: x.string("title"),
          subtitle: x.object("creator").string("nick"),
          artwork: x.object("cover").string("medium_url"), platform: platform)
      }
    case .mg:
      let d = try await json(
        "https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0",
        ["templateVersion": "2", "pageNo": "\(page)"], referer: "https://m.music.migu.cn/")
      guard d.string("code") == "000000" else { throw unavailable(platform) }
      func flatten(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.flatMap { $0["contents"] == nil ? [$0] : flatten($0.array("contents")) }
      }
      return flatten(d.object("data").array("contents")).filter { $0.string("resType") == "2021" }
        .map {
          MusicCollection(
            id: $0.string("resId"), title: $0.string("txt"), subtitle: $0.string("txt2"),
            artwork: $0.string("img"), platform: platform)
        }
    }
  }
  public func tracks(in collection: MusicCollection, page: Int = 1) async throws -> TrackPage {
    let p = collection.platform
    let items: [[String: Any]]
    let total: Int
    switch p {
    case .kw:
      let d: [String: Any]
      if collection.isChart {
        d = try await json(
          "https://kbangserver.kuwo.cn/ksong.s",
          [
            "from": "pc", "fmt": "json", "pn": "\(page-1)", "rn": "100", "type": "bang",
            "data": "content", "id": collection.id, "show_copyright_off": "0", "pcmp4": "1",
            "isbang": "1",
          ])
        guard d["musiclist"] != nil else { throw unavailable(p) }
        items = d.array("musiclist")
        total = d.int("num")
      } else {
        d = try await json(
          "https://nplserver.kuwo.cn/pl.svc",
          [
            "op": "getlistinfo", "pid": collection.id, "pn": "\(page-1)", "rn": "100",
            "encode": "utf8", "keyset": "pl2012", "identity": "kuwo", "pcmp4": "1",
            "vipver": "MUSIC_9.0.5.0_W1", "newver": "1",
          ])
        guard d["musiclist"] != nil else { throw unavailable(p) }
        items = d.array("musiclist")
        total = d.int("total")
      }
    case .wy:
      return try await neteaseTracks(in: collection, page: page)
    case .kg:
      let path = collection.isChart ? "rank/song" : "special/song"
      let d = try await json(
        "http://mobilecdnbj.kugou.com/api/v3/\(path)",
        [
          "version": "9108", "plat": "0", "page": "\(page)", "pagesize": "100",
          collection.isChart ? "rankid" : "specialid": collection.id,
        ])
      guard d.int("status") == 1 else { throw unavailable(p) }
      items = d.object("data").array("info")
      total = d.object("data").int("total")
    case .tx:
      if collection.isChart {
        let d = try await json(
          "https://u.y.qq.com/cgi-bin/musicu.fcg",
          body: [
            "req": [
              "module": "musicToplist.ToplistInfoServer", "method": "GetDetail",
              "param": ["topid": Int(collection.id) ?? 0, "offset": (page - 1) * 100, "num": 100],
            ]
          ], referer: "https://y.qq.com/")
        let r = d.object("req")
        guard r.int("code") == 0, !r.isEmpty else { throw unavailable(p) }
        items = r.object("data").array("songInfoList")
        total = r.object("data").object("data").int("totalNum")
      } else {
        let d = try await json(
          "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg",
          [
            "type": "1", "json": "1", "utf8": "1", "onlysong": "0", "new_format": "1",
            "disstid": collection.id, "format": "json",
          ], referer: "https://y.qq.com/")
        guard d.int("code") == 0, let r = d.array("cdlist").first else { throw unavailable(p) }
        total = r.int("total_song_num")
        items = Array(r.array("songlist").dropFirst((page - 1) * 100).prefix(100))
      }
    case .mg:
      if collection.isChart {
        let d = try await json(
          "https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do",
          ["columnId": collection.id, "needAll": "0"])
        guard d.string("code") == "000000", d["columnInfo"] != nil else { throw unavailable(p) }
        let all = d.object("columnInfo").array("contents").map { $0.object("objectInfo") }
        total = all.count
        items = Array(all.dropFirst((page - 1) * 100).prefix(100))
      } else {
        let d = try await json(
          "https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0",
          ["pageNo": "\(page)", "pageSize": "50", "playlistId": collection.id],
          referer: "https://m.music.migu.cn/")
        guard d.string("code") == "000000", d.object("data")["songList"] != nil else {
          throw unavailable(p)
        }
        items = d.object("data").array("songList")
        total = d.object("data").int("totalCount")
      }
    }
    return TrackPage(
      tracks: Self.unique(items.compactMap { Self.track($0, platform: p) }), total: total)
  }
  private func neteaseTracks(in collection: MusicCollection, page: Int) async throws -> TrackPage {
    guard page > 0 else { throw MusicError.message(L10n.text("页码必须大于零")) }
    // The legacy /api/playlist/detail reports its ten-track preview as trackCount=10.
    // v3 exposes the complete ordered IDs even when tracks contains only the preview.
    let data = try await json(
      "https://music.163.com/api/v3/playlist/detail", ["id": collection.id, "n": "10000"],
      referer: "https://music.163.com/")
    let playlist = data.object("playlist")
    guard data.int("code") == 200, playlist["trackIds"] is [[String: Any]] else {
      throw unavailable(.wy)
    }
    let ids = playlist.array("trackIds").map { $0.string("id") }
    let total = max(playlist.int("trackCount"), ids.count)
    guard ids.count == total, Set(ids).count == ids.count,
      ids.allSatisfy({ (Int64($0) ?? 0) > 0 })
    else {
      throw MusicError.message(L10n.text("网易云列表未完整获取：歌曲 ID 数量与总数不一致，请重试"))
    }
    let wanted = Array(ids.dropFirst((page - 1) * 100).prefix(100))
    guard !wanted.isEmpty else { return TrackPage(tracks: [], total: total) }
    var songs = Dictionary(
      playlist.array("tracks").map { ($0.string("id"), $0) },
      uniquingKeysWith: { first, _ in first })
    let missing = wanted.filter { songs[$0] == nil }
    if !missing.isEmpty {
      try Task.checkCancellation()
      let numericIDs = missing.compactMap(Int64.init)
      let c = try JSONSerialization.data(withJSONObject: numericIDs.map { ["id": $0] })
      let rawIDs = try JSONSerialization.data(withJSONObject: numericIDs)
      let detail = try await json(
        "https://music.163.com/api/v3/song/detail",
        [
          "c": String(decoding: c, as: UTF8.self), "ids": String(decoding: rawIDs, as: UTF8.self),
        ], referer: "https://music.163.com/")
      guard detail.int("code") == 200, detail["songs"] is [[String: Any]] else {
        throw unavailable(.wy)
      }
      for song in detail.array("songs") { songs[song.string("id")] = song }
    }
    // Detail responses may be unordered or omit unavailable songs. Never silently
    // turn a partial response into a complete playlist for playback/save/download.
    let tracks = wanted.compactMap { id in songs[id].flatMap { Self.track($0, platform: .wy) } }
    guard tracks.count == wanted.count else {
      throw MusicError.message(L10n.text("网易云列表未完整获取：本页 \(tracks.count)/\(wanted.count) 首，请重试"))
    }
    return TrackPage(tracks: tracks, total: total)
  }

  public func allTracks(in collection: MusicCollection) async throws -> [Track] {
    var result: [Track] = []
    var expected = 0
    for page in 1...100 {
      try Task.checkCancellation()
      let response = try await tracks(in: collection, page: page)
      expected = max(expected, response.total)
      let old = result.count
      result = Self.unique(result + response.tracks)
      if result.count >= expected && expected > 0 { return result }
      if response.tracks.isEmpty || result.count == old {
        if result.count < expected {
          throw MusicError.message(L10n.text("列表未完整获取：\(result.count)/\(expected) 首，请重试"))
        }
        return result
      }
    }
    throw MusicError.message(L10n.text("列表超过获取上限，请分批处理"))
  }
  private func unavailable(_ p: MusicPlatform) -> MusicError {
    .message(L10n.text("\(p.name)此接口暂不可用，可重试或切换平台。"))
  }
  private static func unique(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert($0.id).inserted }
  }
  static func clean(_ s: String) -> String {
    var value = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
      for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        .reversed()
      {
        guard let range = Range(match.range, in: value),
          let digits = Range(match.range(at: 1), in: value)
        else { continue }
        let number = String(value[digits])
        let code = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
        if let code, let scalar = UnicodeScalar(code) {
          value.replaceSubrange(range, with: String(scalar))
        }
      }
    }
    return value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(
      of: "&quot;", with: "\""
    )
    .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
  }
  public static func track(_ r: [String: Any], platform p: MusicPlatform) -> Track? {
    var id = ""
    var title = ""
    var artist = ""
    var album = ""
    var duration = 0.0
    var art: String?
    var info: [String: JSONValue] = [:]
    var qualities: [String: JSONValue] = [:]
    switch p {
    case .kw:
      id = r.string("MUSICRID", "id").replacingOccurrences(of: "MUSIC_", with: "")
      title = r.string("SONGNAME", "name")
      artist = r.string("ARTIST", "artist")
      album = r.string("ALBUM", "album")
      duration = r.double("DURATION", "duration")
      art = r.string("pic", "albumpic")
      info["albumId"] = .string(r.string("ALBUMID", "albumid"))
      let minfo = r.string("N_MINFO", "n_minfo", "MINFO")
      for (bitrate, quality) in [
        ("128", "128k"), ("320", "320k"), ("2000", "flac"), ("4000", "flac24bit"),
      ] where minfo.contains("bitrate:\(bitrate),") { qualities[quality] = .object([:]) }
    case .wy:
      id = r.string("id")
      title = r.string("name")
      let a = r.object("album", "al")
      album = a.string("name")
      artist = r.array("artists", "ar").map { $0.string("name") }.joined(separator: "、")
      duration = r.double("duration", "dt") / 1000
      art = a.string("picUrl")
      info["albumId"] = .string(a.string("id"))
      info["songmid"] = .number(Double(id) ?? 0)
      for (key, q) in [
        ("lMusic", "128k"), ("l", "128k"), ("hMusic", "320k"), ("h", "320k"), ("sq", "flac"),
        ("hr", "flac24bit"),
      ] where r[key] is [String: Any] { qualities[q] = .object([:]) }
    case .kg:
      id = r.string("Audioid", "audio_id", "hash", "FileHash")
      let filename = r.string("filename", "FileName").components(separatedBy: " - ")
      title = r.string("OriSongName", "SongName")
      if title.isEmpty { title = filename.last ?? "" }
      artist = r.string("SingerName", "singername")
      if artist.isEmpty {
        artist =
          filename.count > 1
          ? filename[0] : r.array("Singers").map { $0.string("name") }.joined(separator: "、")
      }
      album = r.string("AlbumName", "album_name")
      duration = r.double("Duration", "duration")
      info["albumId"] = .string(r.string("AlbumID", "album_id"))
      info["hash"] = .string(r.string("FileHash", "hash"))
      info["albumAudioId"] = .string(r.string("MixSongID", "album_audio_id"))
      for (key, q) in [
        ("FileHash", "128k"), ("hash", "128k"), ("HQFileHash", "320k"), ("320hash", "320k"),
        ("SQFileHash", "flac"), ("sqhash", "flac"), ("ResFileHash", "flac24bit"),
      ] where !r.string(key).isEmpty { qualities[q] = .object(["hash": .string(r.string(key))]) }
    case .tx:
      id = r.string("mid", "songmid")
      title = r.string("title", "name", "songname")
      artist = r.array("singer").map { $0.string("name") }.joined(separator: "、")
      let a = r.object("album")
      album = a.string("name")
      duration = r.double("interval")
      let amid = a.string("mid")
      art = amid.isEmpty ? nil : "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(amid).jpg"
      info["songId"] = .number(r.double("id", "songid"))
      info["albumId"] = .string(amid)
      info["albumMid"] = .string(amid)
      info["strMediaMid"] = .string(r.object("file").string("media_mid"))
      for (key, q) in [
        ("size_128mp3", "128k"), ("size_320mp3", "320k"), ("size_flac", "flac"),
        ("size_hires", "flac24bit"),
      ] where r.object("file").int(key) > 0 { qualities[q] = .object([:]) }
    case .mg:
      id = r.string("songId", "id", "contentId")
      title = r.string("name", "songName", "songTitle")
      artist = r.array("singers", "singerList", "artists").map { $0.string("name", "singerName") }
        .joined(separator: "、")
      if artist.isEmpty { artist = r.string("singer", "singerName") }
      album = r.string("albumName", "album")
      art = r.string("img3", "mediumPic", "largePic", "img1")
      if let image = art, !image.isEmpty, !image.hasPrefix("http") {
        art = "https://d.musicapp.migu.cn" + image
      }
      if art?.isEmpty != false { art = r.array("imgItems", "albumImgs").first?.string("img") }
      duration = r.double("duration")
      if duration == 0 {
        let parts = r.string("length").split(separator: ":")
        if parts.count == 2 { duration = (Double(parts[0]) ?? 0) * 60 + (Double(parts[1]) ?? 0) }
      }
      info["copyrightId"] = .string(r.string("copyrightId"))
      info["albumId"] = .string(r.string("albumId"))
      info["lrcUrl"] = .string(r.string("lrcUrl", "lyricUrl"))
      info["mrcUrl"] = .string(r.string("mrcurl"))
      info["trcUrl"] = .string(r.string("trcUrl"))
      for format in r.array("audioFormats", "rateFormats", "newRateFormats") {
        if let quality = [
          "PQ": "128k", "HQ": "320k", "SQ": "flac", "ZQ24": "flac24bit", "ZQ": "flac24bit",
        ][format.string("formatType")] {
          qualities[quality] = .object([:])
        }
      }
    }
    guard !id.isEmpty, !title.isEmpty else { return nil }
    info["_types"] = .object(qualities)
    info["types"] = .array(
      ["128k", "320k", "flac", "flac24bit"].filter { qualities[$0] != nil }.map { q in
        if case .object(var value) = qualities[q]! {
          value["type"] = .string(q)
          return .object(value)
        }
        return .object(["type": .string(q)])
      })
    return Track(
      platform: p, songID: id, title: clean(title), artist: clean(artist), album: clean(album),
      duration: duration, artwork: art, sourceInfo: info)
  }
}
extension Dictionary where Key == String, Value == Any {
  func string(_ keys: String...) -> String {
    for k in keys {
      if let s = self[k] as? String { return s }
      if let n = self[k] as? NSNumber { return n.stringValue }
    }
    return ""
  }
  func double(_ keys: String...) -> Double {
    for k in keys {
      if let n = self[k] as? NSNumber { return n.doubleValue }
      if let s = self[k] as? String, let n = Double(s) { return n }
    }
    return 0
  }
  func int(_ key: String) -> Int { Int(double(key)) }
  func object(_ keys: String...) -> [String: Any] {
    for k in keys { if let x = self[k] as? [String: Any] { return x } }
    return [:]
  }
  func array(_ keys: String...) -> [[String: Any]] {
    for k in keys { if let x = self[k] as? [[String: Any]] { return x } }
    return []
  }
}

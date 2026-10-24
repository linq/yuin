import CommonCrypto
import CryptoKit
import Foundation
import JavaScriptCore
import Security
import zlib

let context = JSContext()!
var requests: [Int: URLSessionDataTask] = [:]
func emit(_ string: String) { FileHandle.standardOutput.write(Data((string + "\n").utf8)) }
func fail(_ message: String) throws -> Never {
  throw NSError(domain: "MusicSourceHost", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
func bytes(_ a: [String: Any], _ key: String) -> Data {
  Data((a[key] as? [NSNumber] ?? []).map { UInt8(truncating: $0) })
}
func native(_ op: String, _ json: String) -> String {
  do {
    let a = (try JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    let value: Any
    switch op {
    case "encode":
      let s = a["value"] as? String ?? ""
      let encoding = (a["encoding"] as? String ?? "utf8").lowercased()
      let data: Data
      switch encoding {
      case "hex":
        var out = Data()
        var i = s.startIndex
        while i < s.endIndex {
          let end = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
          guard s.distance(from: i, to: end) == 2, let b = UInt8(s[i..<end], radix: 16) else {
            break
          }
          out.append(b)
          i = end
        }
        data = out
      case "base64", "base64url":
        let clean = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
          of: "_", with: "/")
        data =
          Data(
            base64Encoded: clean + String(repeating: "=", count: (4 - clean.count % 4) % 4),
            options: .ignoreUnknownCharacters) ?? Data()
      case "binary", "latin1", "ascii": data = Data(s.utf16.map { UInt8(truncatingIfNeeded: $0) })
      case "utf16le", "ucs2": data = s.data(using: .utf16LittleEndian) ?? Data()
      default: data = Data(s.utf8)
      }
      value = Array(data)
    case "decode":
      let data = bytes(a, "value")
      let encoding = (a["encoding"] as? String ?? "utf8").lowercased()
      switch encoding {
      case "hex": value = data.map { String(format: "%02x", $0) }.joined()
      case "base64": value = data.base64EncodedString()
      case "base64url":
        value = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
          .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
      case "binary", "latin1": value = String(data.map { Character(UnicodeScalar($0)) })
      case "ascii": value = String(data.map { Character(UnicodeScalar($0 & 127)) })
      case "utf16le", "ucs2": value = String(data: data, encoding: .utf16LittleEndian) ?? ""
      default: value = String(decoding: data, as: UTF8.self)
      }
    case "md5":
      value = Insecure.MD5.hash(data: bytes(a, "value")).map { String(format: "%02x", $0) }.joined()
    case "random":
      let size = a["size"] as? Int ?? 0
      guard (0...1_000_000).contains(size) else { try fail("Invalid randomBytes size") }
      if size == 0 { return "{\"value\":[]}" }
      var data = Data(count: size)
      let status = data.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!)
      }
      guard status == errSecSuccess else { try fail("Random generation failed") }
      value = Array(data)
    case "aes":
      let data = bytes(a, "value")
      let key = bytes(a, "key")
      let iv = bytes(a, "iv")
      let mode = (a["mode"] as? String ?? "").lowercased()
      guard
        ["aes-128-cbc", "aes-192-cbc", "aes-256-cbc", "aes-128-ecb", "aes-192-ecb", "aes-256-ecb"]
          .contains(mode), [16, 24, 32].contains(key.count),
        Int(mode.split(separator: "-")[1]) == key.count * 8
      else { try fail("Unsupported AES mode or key length") }
      let ecb = mode.hasSuffix("ecb")
      guard ecb || iv.count == 16 else { try fail("Invalid AES IV") }
      var out = Data(count: data.count + 16)
      var moved = 0
      let capacity = out.count
      let status = out.withUnsafeMutableBytes { o in
        data.withUnsafeBytes { d in
          key.withUnsafeBytes { k in
            iv.withUnsafeBytes { i in
              CCCrypt(
                CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding | (ecb ? kCCOptionECBMode : 0)), k.baseAddress,
                key.count, i.baseAddress, d.baseAddress, data.count, o.baseAddress, capacity, &moved
              )
            }
          }
        }
      }
      guard status == kCCSuccess else { try fail("AES encryption failed") }
      out.count = moved
      value = Array(out)
    case "rsa":
      let pem = a["key"] as? String ?? ""
      let b64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
      guard var der = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
        try fail("Invalid RSA public key")
      }
      if pem.contains("BEGIN PUBLIC KEY") {
        // Unwrap SubjectPublicKeyInfo to its PKCS#1 RSAPublicKey bit string.
        let b = Array(der)
        var index = 0
        func length() -> Int {
          guard index < b.count else { return 0 }
          let n = Int(b[index])
          index += 1
          if n < 128 { return n }
          var value = 0
          for _ in 0..<(n & 127) {
            guard index < b.count else { return 0 }
            value = (value << 8) | Int(b[index])
            index += 1
          }
          return value
        }
        guard b.first == 0x30 else { try fail("Invalid RSA DER") }
        index = 1
        _ = length()
        guard index < b.count, b[index] == 0x30 else { try fail("Invalid RSA algorithm") }
        index += 1
        let algLength = length()
        index += algLength
        guard index < b.count, b[index] == 3 else { try fail("Invalid RSA bit string") }
        index += 1
        let count = length()
        guard count > 1, index + count <= b.count, b[index] == 0 else {
          try fail("Invalid RSA bit string length")
        }
        der = Data(b[(index + 1)..<(index + count)])
      }
      var err: Unmanaged<CFError>?
      guard
        let key = SecKeyCreateWithData(
          der as CFData,
          [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
            as CFDictionary, &err)
      else { try fail("Unsupported RSA key") }
      let input = bytes(a, "value")
      guard input.count <= 128 else { try fail("LX RSA input exceeds 128 bytes") }
      let padded = Data(repeating: 0, count: 128 - input.count) + input
      guard let output = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, padded as CFData, &err)
      else { try fail("RSA encryption failed") }
      value = Array(output as Data)
    case "deflate", "inflate":
      let data = bytes(a, "value")
      var out = Data(
        count: op == "deflate" ? Int(compressBound(uLong(data.count))) : max(1024, data.count * 4))
      var count = uLongf(out.count)
      var status: Int32 = Z_BUF_ERROR
      repeat {
        let capacity = out.count
        count = uLongf(capacity)
        status = out.withUnsafeMutableBytes { o in
          data.withUnsafeBytes { d in
            if op == "deflate" {
              return compress(
                o.bindMemory(to: Bytef.self).baseAddress, &count,
                d.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
            }
            return uncompress(
              o.bindMemory(to: Bytef.self).baseAddress, &count,
              d.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
          }
        }
        if status == Z_BUF_ERROR {
          guard out.count < 32_000_000 else { try fail("Inflated data too large") }
          out = Data(count: min(32_000_000, out.count * 2))
        }
      } while status == Z_BUF_ERROR
      guard status == Z_OK else { try fail("Invalid zlib data") }
      out.count = Int(count)
      value = Array(out)
    default: try fail("Unsupported native operation")
    }
    return String(
      data: try JSONSerialization.data(
        withJSONObject: ["value": value], options: [.fragmentsAllowed]), encoding: .utf8)!
  } catch {
    return String(
      data: try! JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]),
      encoding: .utf8)!
  }
}
context.setObject(
  ({ (s: String) in emit(s) } as @convention(block) (String) -> Void),
  forKeyedSubscript: "__emit" as NSString)
context.setObject(
  ({ (op: String, args: String) -> String in native(op, args) }
    as @convention(block) (String, String) -> String), forKeyedSubscript: "__native" as NSString)
context.setObject(
  ({ (id: Int, delay: Double) in
    DispatchQueue.main.asyncAfter(deadline: .now() + min(delay / 1000, 86400)) {
      context.objectForKeyedSubscript("__timer")?.call(withArguments: [id])
    }
  } as @convention(block) (Int, Double) -> Void), forKeyedSubscript: "__schedule" as NSString)
context.setObject(
  ({ (id: Int) in requests.removeValue(forKey: id)?.cancel() } as @convention(block) (Int) -> Void),
  forKeyedSubscript: "__cancelHTTP" as NSString)
context.setObject(
  ({ (id: Int, urlString: String, options: String) in
    func reply(_ error: String?, _ response: [String: Any]? = nil) {
      context.objectForKeyedSubscript("__httpReply")?.call(withArguments: [
        id, error as Any? ?? NSNull(), response as Any? ?? NSNull(),
      ])
    }
    guard let url = URL(string: urlString),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
    else {
      reply("Only HTTP(S) requests are supported")
      return
    }
    let opts =
      (try? JSONSerialization.jsonObject(with: Data(options.utf8))) as? [String: Any] ?? [:]
    var req = URLRequest(url: url)
    req.httpMethod = (opts["method"] as? String ?? "GET").uppercased()
    req.timeoutInterval = min(60, max(1, (opts["timeout"] as? Double ?? 60000) / 1000))
    for (key, value) in opts["headers"] as? [String: Any] ?? [:] {
      req.setValue(String(describing: value), forHTTPHeaderField: key)
    }
    if let body = opts["body"] as? String {
      req.httpBody = Data(body.utf8)
    } else if let body = opts["body"] as? [String: Any], body["type"] as? String == "Buffer" {
      req.httpBody = bytes(body, "data")
    } else if let body = opts["body"] {
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
      if req.value(forHTTPHeaderField: "Content-Type") == nil {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    } else if let form = opts["form"] as? [String: Any] {
      var c = URLComponents()
      c.queryItems = form.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
      req.httpBody = Data(
        (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
      req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    } else if let form = opts["formData"] as? [String: Any] {
      let boundary = "MyMusic-" + UUID().uuidString
      var data = Data()
      for (key, value) in form {
        let safe = key.replacingOccurrences(of: "\"", with: "").replacingOccurrences(
          of: "\r", with: ""
        ).replacingOccurrences(of: "\n", with: "")
        data.append(
          Data(
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(safe)\"\r\n\r\n\(value)\r\n"
              .utf8))
      }
      data.append(Data("--\(boundary)--\r\n".utf8))
      req.httpBody = data
      req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    }
    let task = URLSession.shared.dataTask(with: req) { data, response, error in
      DispatchQueue.main.async {
        requests.removeValue(forKey: id)
        if let error {
          reply(error.localizedDescription)
          return
        }
        guard let data, let r = response as? HTTPURLResponse, data.count <= 32_000_000 else {
          reply("Invalid or oversized response")
          return
        }
        let body =
          (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
          ?? String(decoding: data, as: UTF8.self)
        var headers: [String: String] = [:]
        for (key, value) in r.allHeaderFields {
          headers[String(describing: key).lowercased()] = String(describing: value)
        }
        reply(
          nil,
          [
            "statusCode": r.statusCode,
            "statusMessage": HTTPURLResponse.localizedString(forStatusCode: r.statusCode),
            "headers": headers, "raw": data.base64EncodedString(), "body": body,
          ])
      }
    }
    requests[id] = task
    task.resume()
  } as @convention(block) (Int, String, String) -> Void), forKeyedSubscript: "__http" as NSString)
let bridgeURL = Bundle.module.url(forResource: "bridge", withExtension: "js")!
context.evaluateScript(try String(contentsOf: bridgeURL, encoding: .utf8))
DispatchQueue.global().async {
  while let line = readLine() {
    guard let data = line.data(using: .utf8), data.count <= 12_000_000,
      let command = try? JSONSerialization.jsonObject(with: data)
    else { continue }
    DispatchQueue.main.async {
      context.objectForKeyedSubscript("__command")?.call(withArguments: [command])
    }
  }
  exit(0)
}
RunLoop.main.run()

import Foundation
import JavaScriptCore

struct PluginManifest: Codable, Hashable, Sendable {
    var platform: String
    var version: String?
    var author: String?
    var description: String?
    var sourceURL: String?
    var supportedSearchTypes: [MediaType]
    var supportedMethods: Set<String>
    var userVariables: [PluginUserVariable]
}

struct PluginUserVariable: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var name: String?
    var hint: String?
    var id: String { key }
}

enum PluginRuntimeError: LocalizedError {
    case invalidPlugin(String)
    case unsupportedMethod(String)
    case execution(String)
    case request(String)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidPlugin(let message):
            String(format: String(localized: "插件无法解析：%@"), message)
        case .unsupportedMethod(let method):
            String(format: String(localized: "插件不支持 %@"), method)
        case .execution(let message):
            String(format: String(localized: "插件执行失败：%@"), message)
        case .request(let message):
            String(format: String(localized: "网络请求失败：%@"), message)
        case .timeout:
            String(localized: "插件执行超时")
        case .invalidResponse:
            String(localized: "插件返回了无法识别的数据")
        }
    }
}

final class PluginRuntime: @unchecked Sendable {
    let code: String
    let sourceURL: URL?

    private let queue: DispatchQueue
    private let lock = NSLock()
    private let session: URLSession
    private var context: JSContext?
    private var pending: [String: (Result<JSONValue, Error>) -> Void] = [:]
    private(set) var manifest: PluginManifest?

    init(code: String, sourceURL: URL?) {
        self.code = code
        self.sourceURL = sourceURL
        self.queue = DispatchQueue(label: "app.sonnets.plugin.\(UUID().uuidString)", qos: .userInitiated)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        self.session = URLSession(configuration: configuration)
    }

    func prepare(userVariables: [String: String] = [:]) async throws -> PluginManifest {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return }
                do {
                    let manifest = try self.prepareSynchronously(userVariables: userVariables)
                    continuation.resume(returning: manifest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func invoke(_ method: String, arguments: [JSONValue], timeout: TimeInterval = 20) async throws -> JSONValue {
        guard manifest?.supportedMethods.contains(method) == true else {
            throw PluginRuntimeError.unsupportedMethod(method)
        }
        let callID = UUID().uuidString
        let argumentsData = try JSONEncoder().encode(arguments)
        guard let argumentsJSON = String(data: argumentsData, encoding: .utf8) else {
            throw PluginRuntimeError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[callID] = { result in continuation.resume(with: result) }
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(callID: callID, result: .failure(PluginRuntimeError.timeout))
            }

            queue.async { [weak self] in
                guard let self, let context = self.context else {
                    self?.finish(
                        callID: callID,
                        result: .failure(
                            PluginRuntimeError.invalidPlugin(String(localized: "运行环境未初始化"))
                        )
                    )
                    return
                }
                let callIDLiteral = Self.javaScriptString(callID)
                let methodLiteral = Self.javaScriptString(method)
                let script = "__musicfreeInvoke(\(callIDLiteral), \(methodLiteral), \(argumentsJSON));"
                _ = context.evaluateScript(script)
                if let exception = context.exception {
                    context.exception = nil
                    self.finish(callID: callID, result: .failure(PluginRuntimeError.execution(exception.toString())))
                }
            }
        }
    }

    private func prepareSynchronously(userVariables: [String: String]) throws -> PluginManifest {
        guard let context = JSContext() else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "JavaScriptCore 初始化失败"))
        }
        self.context = context

        var capturedException: String?
        context.exceptionHandler = { _, exception in
            capturedException = exception?.toString()
        }

        installNativeBridges(in: context)

        guard
            let bufferURL = Bundle.main.url(forResource: "MusicFreeBuffer", withExtension: "js"),
            let bufferCode = try? String(contentsOf: bufferURL, encoding: .utf8),
            let vendorURL = Bundle.main.url(forResource: "MusicFreeVendor", withExtension: "js"),
            let vendorCode = try? String(contentsOf: vendorURL, encoding: .utf8)
        else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "缺少插件兼容组件"))
        }
        context.evaluateScript(bufferCode, withSourceURL: bufferURL)
        if let capturedException { throw PluginRuntimeError.invalidPlugin(capturedException) }
        context.evaluateScript(Self.fetchCompatibilityScript)
        if let capturedException { throw PluginRuntimeError.invalidPlugin(capturedException) }
        context.evaluateScript(vendorCode, withSourceURL: vendorURL)
        if let capturedException { throw PluginRuntimeError.invalidPlugin(capturedException) }

        let variablesData = try JSONEncoder().encode(userVariables)
        let variablesJSON = String(data: variablesData, encoding: .utf8) ?? "{}"
        context.evaluateScript(Self.bootstrapScript(userVariablesJSON: variablesJSON))
        if let capturedException { throw PluginRuntimeError.invalidPlugin(capturedException) }

        context.evaluateScript(code, withSourceURL: sourceURL ?? URL(string: "musicfree-plugin://local/plugin.js")!)
        if let capturedException { throw PluginRuntimeError.invalidPlugin(capturedException) }

        guard
            let metadataJSON = context.evaluateScript("__musicfreeMetadata()")?.toString(),
            let metadataData = metadataJSON.data(using: .utf8),
            let metadataObject = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
            let platform = metadataObject["platform"] as? String,
            !platform.isEmpty
        else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "缺少 platform"))
        }

        let searchTypes = (metadataObject["supportedSearchType"] as? [String] ?? ["music"])
            .compactMap(MediaType.init(rawValue:))
        let userVariableObjects = metadataObject["userVariables"] as? [[String: Any]] ?? []
        let parsedUserVariables = userVariableObjects.compactMap { object -> PluginUserVariable? in
            guard let key = object["key"] as? String, !key.isEmpty else { return nil }
            return PluginUserVariable(key: key, name: object["name"] as? String, hint: object["hint"] as? String)
        }
        let manifest = PluginManifest(
            platform: platform,
            version: metadataObject["version"] as? String,
            author: metadataObject["author"] as? String,
            description: metadataObject["description"] as? String,
            sourceURL: metadataObject["srcUrl"] as? String,
            supportedSearchTypes: searchTypes.isEmpty ? [.music] : searchTypes,
            supportedMethods: Set(metadataObject["methods"] as? [String] ?? []),
            userVariables: parsedUserVariables
        )
        self.manifest = manifest
        return manifest
    }

    private func installNativeBridges(in context: JSContext) {
        let completionBlock: @convention(block) (String, String) -> Void = { [weak self] callID, payload in
            guard let self else { return }
            do {
                let data = Data(payload.utf8)
                let envelope = try JSONDecoder().decode(PluginCallEnvelope.self, from: data)
                if envelope.ok {
                    self.finish(callID: callID, result: .success(envelope.value ?? .null))
                } else {
                    self.finish(
                        callID: callID,
                        result: .failure(
                            PluginRuntimeError.execution(envelope.error ?? String(localized: "未知错误"))
                        )
                    )
                }
            } catch {
                self.finish(callID: callID, result: .failure(PluginRuntimeError.invalidResponse))
            }
        }
        context.setObject(completionBlock, forKeyedSubscript: "__nativeComplete" as NSString)

        let logBlock: @convention(block) (String, String) -> Void = { level, message in
            #if DEBUG
            print("[MusicFree][\(level)] \(message)")
            #endif
        }
        context.setObject(logBlock, forKeyedSubscript: "__nativeLog" as NSString)

        let requestBlock: @convention(block) (String, JSValue, JSValue) -> Void = { [weak self] requestJSON, resolve, reject in
            self?.performNativeRequest(requestJSON: requestJSON, resolve: resolve, reject: reject)
        }
        context.setObject(requestBlock, forKeyedSubscript: "__nativeRequest" as NSString)
    }

    private func performNativeRequest(requestJSON: String, resolve: JSValue, reject: JSValue) {
        let resolveValue = resolve
        let rejectValue = reject
        let callbackQueue = queue

        do {
            let configuration = try JSONDecoder().decode(NativeRequestConfiguration.self, from: Data(requestJSON.utf8))
            guard let url = URL(string: configuration.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw PluginRuntimeError.request(String(localized: "仅允许 HTTP/HTTPS 地址"))
            }
            var request = URLRequest(url: url)
            request.httpMethod = (configuration.method ?? "GET").uppercased()
            request.timeoutInterval = max(2, min((configuration.timeout ?? 15_000) / 1_000, 60))
            configuration.headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let body = configuration.body {
                switch body {
                case .string(let value):
                    request.httpBody = Data(value.utf8)
                case .null:
                    break
                default:
                    request.httpBody = try JSONEncoder().encode(body)
                    if request.value(forHTTPHeaderField: "Content-Type") == nil {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
            }

            session.dataTask(with: request) { data, response, error in
                if let error {
                    callbackQueue.async { _ = rejectValue.call(withArguments: [error.localizedDescription]) }
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    callbackQueue.async { _ = rejectValue.call(withArguments: ["无效网络响应"]) }
                    return
                }
                let data = data ?? Data()
                let responseData: Any
                if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    responseData = object
                } else {
                    responseData = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                }
                let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                    result[String(describing: entry.key).lowercased()] = String(describing: entry.value)
                }
                let envelope: [String: Any] = [
                    "data": responseData,
                    "status": httpResponse.statusCode,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    "headers": headers,
                    "config": ["url": configuration.url]
                ]
                guard let payloadData = try? JSONSerialization.data(withJSONObject: envelope, options: [.fragmentsAllowed]),
                      let payload = String(data: payloadData, encoding: .utf8) else {
                    callbackQueue.async { _ = rejectValue.call(withArguments: ["响应序列化失败"]) }
                    return
                }
                callbackQueue.async {
                    if (200..<400).contains(httpResponse.statusCode) {
                        _ = resolveValue.call(withArguments: [payload])
                    } else {
                        _ = rejectValue.call(withArguments: ["HTTP \(httpResponse.statusCode)"])
                    }
                }
            }.resume()
        } catch {
            callbackQueue.async { _ = rejectValue.call(withArguments: [error.localizedDescription]) }
        }
    }

    private func finish(callID: String, result: Result<JSONValue, Error>) {
        let completion: ((Result<JSONValue, Error>) -> Void)?
        lock.lock()
        completion = pending.removeValue(forKey: callID)
        lock.unlock()
        completion?(result)
    }

    private static func javaScriptString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static let fetchCompatibilityScript = #"""
    (function () {
      'use strict';
      function Headers(initial) {
        this.values = {};
        const self = this;
        if (initial && typeof initial.forEach === 'function') {
          initial.forEach((value, key) => self.set(key, value));
        } else {
          Object.keys(initial || {}).forEach(key => self.set(key, initial[key]));
        }
      }
      Headers.prototype.set = function (key, value) { this.values[String(key).toLowerCase()] = String(value); };
      Headers.prototype.append = function (key, value) {
        const name = String(key).toLowerCase();
        this.values[name] = this.values[name] ? this.values[name] + ', ' + value : String(value);
      };
      Headers.prototype.get = function (key) { return this.values[String(key).toLowerCase()] || null; };
      Headers.prototype.has = function (key) { return Object.prototype.hasOwnProperty.call(this.values, String(key).toLowerCase()); };
      Headers.prototype.forEach = function (callback) {
        Object.keys(this.values).forEach(key => callback(this.values[key], key, this));
      };

      function responseBody(data) {
        return typeof data === 'string' ? data : JSON.stringify(data === undefined ? null : data);
      }

      globalThis.Headers = globalThis.Headers || Headers;
      globalThis.AbortController = globalThis.AbortController || function () {
        this.signal = { aborted: false, addEventListener: function () {}, removeEventListener: function () {} };
        this.abort = () => { this.signal.aborted = true; };
      };
      globalThis.fetch = function (input, options) {
        const config = options || {};
        const url = typeof input === 'string' ? input : String(input && input.url || input);
        const headers = {};
        new Headers(config.headers || {}).forEach((value, key) => headers[key] = value);
        return new Promise((resolve, reject) => {
          __nativeRequest(JSON.stringify({
            url: url,
            method: String(config.method || 'GET'),
            headers: headers,
            body: config.body === undefined ? null : config.body,
            timeout: 30000
          }), payload => {
            try {
              const packet = JSON.parse(payload);
              const text = responseBody(packet.data);
              const response = {
                ok: packet.status >= 200 && packet.status < 300,
                status: packet.status,
                statusText: packet.statusText || '',
                url: url,
                headers: new Headers(packet.headers || {}),
                text: () => Promise.resolve(text),
                json: () => Promise.resolve(typeof packet.data === 'string' ? JSON.parse(packet.data) : packet.data),
                clone: function () { return this; }
              };
              resolve(response);
            } catch (error) { reject(error); }
          }, message => reject(new Error(String(message))));
        });
      };
    })();
    """#

    private static func bootstrapScript(userVariablesJSON: String) -> String {
        #"""
        (function () {
          'use strict';
          const packages = globalThis.__musicfreePackages || {};

          function encodeQuery(value, prefix, output) {
            if (value === undefined || value === null) return;
            if (Array.isArray(value)) {
              value.forEach((item, index) => encodeQuery(item, prefix + '[' + index + ']', output));
            } else if (typeof value === 'object') {
              Object.keys(value).forEach(key => encodeQuery(value[key], prefix ? prefix + '[' + key + ']' : key, output));
            } else {
              output.push(encodeURIComponent(prefix) + '=' + encodeURIComponent(String(value)));
            }
          }

          function queryString(value) {
            const output = [];
            Object.keys(value || {}).forEach(key => encodeQuery(value[key], key, output));
            return output.join('&');
          }

          function merge(base, extra) {
            const result = {};
            Object.keys(base || {}).forEach(key => result[key] = base[key]);
            Object.keys(extra || {}).forEach(key => {
              if (key === 'headers') result.headers = Object.assign({}, base && base.headers || {}, extra.headers || {});
              else result[key] = extra[key];
            });
            return result;
          }

          function createAxios(defaults) {
            function axios(configOrURL, maybeConfig) {
              let config = typeof configOrURL === 'string' ? merge(maybeConfig || {}, { url: configOrURL }) : (configOrURL || {});
              config = merge(defaults || {}, config);
              let url = config.url;
              const query = queryString(config.params || {});
              if (query) url += (url.indexOf('?') >= 0 ? '&' : '?') + query;
              const headers = {};
              Object.keys(config.headers || {}).forEach(key => headers[key] = String(config.headers[key]));
              const request = {
                url: url,
                method: String(config.method || 'get'),
                headers: headers,
                body: config.data === undefined ? null : config.data,
                timeout: Number(config.timeout || axios.defaults.timeout || 15000)
              };
              return new Promise((resolve, reject) => {
                __nativeRequest(JSON.stringify(request), payload => {
                  try { resolve(JSON.parse(payload)); } catch (error) { reject(error); }
                }, message => reject(new Error(String(message))));
              });
            }
            axios.get = (url, config) => axios(merge(config || {}, { url: url, method: 'get' }));
            axios.delete = (url, config) => axios(merge(config || {}, { url: url, method: 'delete' }));
            axios.post = (url, data, config) => axios(merge(config || {}, { url: url, data: data, method: 'post' }));
            axios.put = (url, data, config) => axios(merge(config || {}, { url: url, data: data, method: 'put' }));
            axios.patch = (url, data, config) => axios(merge(config || {}, { url: url, data: data, method: 'patch' }));
            axios.create = config => createAxios(merge(defaults || {}, config || {}));
            axios.defaults = merge({ timeout: 15000 }, defaults || {});
            axios.interceptors = { request: { use: function () {} }, response: { use: function () {} } };
            axios.default = axios;
            return axios;
          }

          const axios = createAxios({});
          packages.axios = axios;
          packages.qs = packages.qs || { stringify: queryString };
          globalThis.__musicfree_require = function (name) {
            const value = packages[name];
            if (!value) throw new Error('Unsupported package: ' + name);
            if (value.default === undefined) {
              try { value.default = value; } catch (_) {}
            }
            return value;
          };
          globalThis.require = globalThis.__musicfree_require;
          globalThis.module = { exports: {} };
          globalThis.exports = globalThis.module.exports;
          globalThis.env = {
            appVersion: '1.0.0',
            os: 'ios',
            lang: 'zh-CN',
            userVariables: \#(userVariablesJSON),
            getUserVariables: function () { return this.userVariables || {}; }
          };
          globalThis.process = { platform: 'ios', version: '1.0.0', env: globalThis.env };
          globalThis.console = {
            log: (...items) => __nativeLog('log', items.map(String).join(' ')),
            info: (...items) => __nativeLog('info', items.map(String).join(' ')),
            warn: (...items) => __nativeLog('warn', items.map(String).join(' ')),
            error: (...items) => __nativeLog('error', items.map(String).join(' '))
          };

          globalThis.__musicfreeMetadata = function () {
            const plugin = module.exports && module.exports.default ? module.exports.default : module.exports;
            return JSON.stringify({
              platform: plugin.platform,
              version: plugin.version,
              author: plugin.author,
              description: plugin.description,
              srcUrl: plugin.srcUrl,
              supportedSearchType: plugin.supportedSearchType || ['music'],
              userVariables: plugin.userVariables || [],
              methods: Object.keys(plugin).filter(key => typeof plugin[key] === 'function')
            });
          };

          globalThis.__musicfreeInvoke = function (callID, method, args) {
            const plugin = module.exports && module.exports.default ? module.exports.default : module.exports;
            if (!plugin || typeof plugin[method] !== 'function') {
              __nativeComplete(callID, JSON.stringify({ ok: false, error: 'Unsupported method: ' + method }));
              return;
            }
            Promise.resolve().then(() => plugin[method].apply(plugin, args || [])).then(value => {
              __nativeComplete(callID, JSON.stringify({ ok: true, value: value === undefined ? null : value }));
            }).catch(error => {
              __nativeComplete(callID, JSON.stringify({ ok: false, error: String(error && (error.stack || error.message) || error) }));
            });
          };
        })();
        """#
    }
}

private struct PluginCallEnvelope: Codable {
    var ok: Bool
    var value: JSONValue?
    var error: String?
}

private struct NativeRequestConfiguration: Codable {
    var url: String
    var method: String?
    var headers: [String: String]?
    var body: JSONValue?
    var timeout: TimeInterval?
}

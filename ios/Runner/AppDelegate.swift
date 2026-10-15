import Flutter
import UIKit
import WebKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var commentInputChannel: FlutterMethodChannel?
  private var proxyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set WebKit language preferences before any WebView is created.
    let defaults = UserDefaults.standard
    defaults.set(["en-US", "en"], forKey: "AppleLanguages")
    defaults.set("en_US", forKey: "AppleLocale")
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      proxyChannel = FlutterMethodChannel(
        name: "test_tiktok/webview_proxy", binaryMessenger: controller.binaryMessenger
      )
      proxyChannel?.setMethodCallHandler { call, result in
        guard call.method == "configure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let arguments = call.arguments as? [String: Any]
        let host = arguments?["host"] as? String
        guard #available(iOS 17.0, *) else {
          if host == nil {
            result(nil)
          } else {
            result(FlutterError(code: "proxy_unsupported",
              message: "Cấu hình proxy cần iOS 17 trở lên.", details: nil))
          }
          return
        }
        let dataStore = WKWebsiteDataStore.default()
        guard let host = host, !host.isEmpty else {
          dataStore.proxyConfigurations = []
          result(nil)
          return
        }
        guard let port = arguments?["port"] as? Int,
              (1...65535).contains(port),
              let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)),
              let scheme = arguments?["scheme"] as? String,
              scheme == "http" || scheme == "https" else {
          result(FlutterError(code: "proxy_invalid",
            message: "Proxy không hợp lệ.", details: nil))
          return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: endpointPort)
        let proxy = ProxyConfiguration(httpCONNECTProxy: endpoint,
          tlsOptions: scheme == "https" ? NWProtocolTLS.Options() : nil)
        let username = arguments?["username"] as? String ?? ""
        if !username.isEmpty {
          proxy.applyCredential(username: username,
            password: arguments?["password"] as? String ?? "")
        }
        dataStore.proxyConfigurations = [proxy]
        result(nil)
      }
      commentInputChannel = FlutterMethodChannel(
        name: "test_tiktok/comment_input", binaryMessenger: controller.binaryMessenger
      )
      commentInputChannel?.setMethodCallHandler { [weak self, weak controller] call, result in
        guard call.method == "paste" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let self = self, let controller = controller,
              let webView = self.findWebView(in: controller.view),
              UIPasteboard.general.hasStrings else {
          result(false)
          return
        }
        let arguments = call.arguments as? [String: Any]
        let context = arguments?["context"] as? String ?? "comment"
        let guardScript: String
        if (context == "signup" || context == "login"), let attempt = arguments?["attempt"] as? Int {
          let stateName = context == "signup" ? "__flutterAutoSignup" : "__flutterAutoLogin"
          guardScript = "window.\(stateName)?.canPasteFromClipboard(\(attempt)) === true"
        } else if context == "comment" {
          guardScript = """
          (() => {
            if (document.hidden || window.__flutterAutoWatch?.getStatus?.().commentStage !== 'pasting') return false;
            const e = document.activeElement;
            return !!e && !!e.closest('[data-e2e="comment-text"], [data-e2e="comment-input"]') &&
              (e.isContentEditable || e.tagName === 'TEXTAREA');
          })()
          """
        } else {
          result(false)
          return
        }
        webView.evaluateJavaScript(guardScript) { value, error in
          guard error == nil, value as? Bool == true else {
            result(false)
            return
          }
          let target = self.findFirstResponder(in: webView) ?? webView
          let action = #selector(UIResponderStandardEditActions.paste(_:))
          guard target.canPerformAction(action, withSender: nil) else {
            result(false)
            return
          }
          result(UIApplication.shared.sendAction(action, to: target, from: nil, for: nil))
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func findWebView(in view: UIView) -> WKWebView? {
    if let webView = view as? WKWebView { return webView }
    for child in view.subviews {
      if let webView = findWebView(in: child) { return webView }
    }
    return nil
  }

  private func findFirstResponder(in view: UIView) -> UIResponder? {
    if view.isFirstResponder { return view }
    for child in view.subviews {
      if let responder = findFirstResponder(in: child) { return responder }
    }
    return nil
  }
}

import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var commentInputChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
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
        if context == "signup", let attempt = arguments?["attempt"] as? Int {
          guardScript = "window.__flutterAutoSignup?.canPasteFromClipboard(\(attempt)) === true"
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

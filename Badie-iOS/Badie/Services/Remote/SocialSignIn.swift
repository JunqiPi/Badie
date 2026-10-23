import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - Apple / Google 登录用的一次性随机串

/// Apple 和 Google 都一样：发给对方的是 nonce 的 SHA-256，交给 Supabase 的是原文，Supabase 核对两者对得上，
/// 别人截到身份令牌也没法重放。Google 的登录页还用 PKCE：发出去的是 verifier 的哈希，换令牌时才交出原文
enum SocialSignIn {
    /// Google Cloud 里 iOS 类型的 OAuth 客户端 ID（公开的，不是密钥；Supabase 的 Google 设置里也要加上它）。
    /// 没填时 App 里不显示 Google 按钮
    static let googleClientID: String? = nil

    static func randomString(bytes count: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    /// Apple 要的是十六进制的 SHA-256
    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// PKCE 的 S256：SHA-256 再 base64url（不带 =）
    static func pkceChallenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Google（直接打开 Google 的登录页）

/// 不经过 Supabase 的网址：系统弹窗和 Google 页面上显示的是 google.com 和 Badie。
/// 登录完 Google 跳回 com.googleusercontent.apps.…（客户端 ID 倒过来写），用 code 换 Google 的身份令牌，再像 Apple 一样交给 Supabase
struct GoogleSignIn {
    let clientID: String
    let verifier = SocialSignIn.randomString()
    let nonce = SocialSignIn.randomString()
    let state = SocialSignIn.randomString(bytes: 16)

    /// 跳回 App 用的 scheme：客户端 ID 倒过来写
    var scheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    var redirect: String { "\(scheme):/oauthredirect" }

    var url: URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: SocialSignIn.pkceChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: SocialSignIn.sha256Hex(nonce)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components?.url
    }

    /// 跳回来的地址里取 code；state 对不上（不是这次发起的）或者对方报错（比如点了取消）时为空
    func code(from callback: URL) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { return nil }
        return items.first { $0.name == "code" }?.value
    }

    /// 用 code 和 verifier 换 Google 的身份令牌（iOS 客户端不需要密钥）
    func idToken(code: String, transport: SupabaseClient.Transport = { try await URLSession.shared.data(for: $0) }) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
        // “+” 在表单里会被当成空格，要转义
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await transport(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id_token"] as? String else {
            throw RemoteError.server("google_no_token")
        }
        return token
    }
}

// MARK: - Sign in with Apple（系统弹窗）

/// 用我们自己样式的按钮触发系统的 Apple 授权弹窗（Apple 允许自定义按钮：黑 / 白底、Apple 标志、“通过 Apple 继续”）。
/// 返回身份令牌、交给 Supabase 用的 nonce 原文，和 Apple 只在第一次授权时给的名字
@MainActor
final class AppleSignIn: NSObject {
    struct Credential {
        let idToken: String
        let nonce: String
        let givenName: String?
        /// 一次性授权码（5 分钟内有效）：注销时交给服务器去撤销 Apple 授权
        let authorizationCode: String?
    }

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func run() async throws -> Credential {
        let nonce = SocialSignIn.randomString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SocialSignIn.sha256Hex(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        let credential = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
        guard let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw RemoteError.server("apple_no_token")
        }
        return Credential(idToken: token, nonce: nonce, givenName: credential.fullName?.givenName,
                          authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
    }

    /// 用户自己关掉了弹窗：不算出错，不用提示
    static func isCancel(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        Task { @MainActor in
            if let credential {
                self.finish(.success(credential))
            } else {
                self.finish(.failure(RemoteError.server("apple_no_credential")))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - Apple / Google 登录用的一次性随机串

/// Sign in with Apple：发给 Apple 的是 nonce 的 SHA-256，交给 Supabase 的是原文，Supabase 核对两者对得上，
/// 别人截到身份令牌也没法重放。Google 走网页式登录：PKCE，发出去的是 verifier 的哈希，换令牌时才交出原文
enum SocialSignIn {
    /// 系统浏览器登录完跳回 App 的地址（Supabase 后台的 Redirect URLs 里要有它）
    static let callbackScheme = "badie"
    static let redirect = "badie://auth-callback"

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

    /// 跳回来的地址里取 code；对方报错（比如点了取消）时没有 code
    static func code(from callback: URL) -> String? {
        URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

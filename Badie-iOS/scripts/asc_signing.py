"""给 GitHub Actions 上传 TestFlight 准备签名：用 App Store Connect API 建一张 Apple Distribution 证书，
给 App 和它的扩展（通知扩展）各建一份 App Store 描述文件。

云端的 Mac 每次都是新的，证书的私钥又只能在建的时候拿到，所以每次运行都建一张新的。
上一次运行留下的证书在下一次开始时吊销（不在上传后马上吊销，免得 App Store Connect 还在处理那个 Build）；
TestFlight 和 App Store 上的 App 由 Apple 重新签名，吊销不影响它们。只用 Python 标准库和系统自带的 openssl。

用法：python3 asc_signing.py <输出目录> >> "$GITHUB_OUTPUT"
环境变量：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH（.p8 文件）、PROFILE_NAME（描述文件名的前缀）、
BUNDLE_IDS（空格隔开，第一个是 App，要先在网页上注册好；后面的扩展没注册就自动注册）
输出目录里写 key.pem、cert.cer、profiles/<UUID>.mobileprovision；标准输出是 team_id=…
描述文件叫“<PROFILE_NAME> <Bundle ID>”，构建时用 PROVISIONING_PROFILE_SPECIFIER="<PROFILE_NAME> $(PRODUCT_BUNDLE_IDENTIFIER)"
"""
import base64
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_NAME = os.environ.get("PROFILE_NAME", "Badie GitHub Actions")
# macOS 自带的 LibreSSL；Homebrew 的 OpenSSL 3 导出的 .p12 钥匙串导入不了
OPENSSL = "/usr/bin/openssl" if os.path.exists("/usr/bin/openssl") else "openssl"


def log(message):
    print(message, file=sys.stderr)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_signature(der):
    """openssl 给的 ECDSA 签名是 DER（SEQUENCE { INTEGER r, INTEGER s }），JWT 要 r 和 s 各 32 字节拼起来"""
    assert der[0] == 0x30 and der[1] < 0x80, "unexpected signature"
    parts, i = [], 2
    while i < len(der):
        assert der[i] == 0x02, "unexpected signature"
        length = der[i + 1]
        parts.append(der[i + 2:i + 2 + length].lstrip(b"\0").rjust(32, b"\0"))
        i += 2 + length
    return b"".join(parts)


def make_token():
    """App Store Connect API 的 JWT（ES256，20 分钟有效）"""
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200,
                                "aud": "appstoreconnect-v1"}).encode())
    signed = f"{header}.{claims}".encode()
    der = subprocess.run([OPENSSL, "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=signed, capture_output=True, check=True).stdout
    return f"{header}.{claims}.{b64url(raw_signature(der))}"


class ApiError(Exception):
    pass


def api(method, path, body=None, missing_ok=False):
    request = urllib.request.Request(API + path, method=method,
                                     data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        try:
            errors = json.loads(error.read()).get("errors", [])
        except ValueError:
            errors = []
        details = "; ".join(e.get("detail") or e.get("title", "") for e in errors)
        raise ApiError(f"{method} {path.split('?')[0]} → HTTP {error.code}: {details}") from None


def find_bundle_id(identifier, register=False):
    query = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 200})
    for bundle in api("GET", f"/bundleIds?{query}")["data"]:
        if bundle["attributes"]["identifier"] == identifier:
            return bundle["id"]
    if not register:
        raise ApiError(f"Bundle ID {identifier} 还没注册：按 Badie-iOS/docs/APP_STORE.md 第 2 节第 1 步注册")
    # 扩展不用额外的权限，直接注册
    body = {"data": {"type": "bundleIds",
                     "attributes": {"identifier": identifier, "name": identifier.replace(".", " "), "platform": "IOS"}}}
    log(f"已注册 {identifier}")
    return api("POST", "/bundleIds", body)["data"]["id"]


def revoke_previous():
    """删掉上一次运行留下的描述文件，吊销它们用的证书（只动我们自己建的，按描述文件名字的前缀认）"""
    query = urllib.parse.urlencode({"filter[profileType]": "IOS_APP_STORE", "include": "certificates", "limit": 200})
    certificates = set()
    for profile in api("GET", f"/profiles?{query}")["data"]:
        if not profile["attributes"]["name"].startswith(PROFILE_NAME):
            continue
        certificates.update(c["id"] for c in profile.get("relationships", {}).get("certificates", {}).get("data") or [])
        api("DELETE", f"/profiles/{profile['id']}", missing_ok=True)
    for certificate in certificates:
        api("DELETE", f"/certificates/{certificate}", missing_ok=True)
    log(f"已清理上一次的描述文件和 {len(certificates)} 张证书")


def create_certificate(out):
    key, csr = os.path.join(out, "key.pem"), os.path.join(out, "request.csr")
    subprocess.run([OPENSSL, "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key,
                    "-subj", f"/CN={PROFILE_NAME}", "-out", csr], check=True, capture_output=True)
    with open(csr) as f:
        body = {"data": {"type": "certificates",
                         "attributes": {"certificateType": "DISTRIBUTION", "csrContent": f.read()}}}
    certificate = api("POST", "/certificates", body)["data"]
    with open(os.path.join(out, "cert.cer"), "wb") as f:
        f.write(base64.b64decode(certificate["attributes"]["certificateContent"]))
    return certificate["id"]


def create_profile(out, identifier, bundle_id, certificate_id):
    body = {"data": {"type": "profiles",
                     "attributes": {"name": f"{PROFILE_NAME} {identifier}", "profileType": "IOS_APP_STORE"},
                     "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                                       "certificates": {"data": [{"type": "certificates", "id": certificate_id}]}}}}
    content = base64.b64decode(api("POST", "/profiles", body)["data"]["attributes"]["profileContent"])
    # 描述文件是签了名的 plist，取出里面的 plist 读 Team ID 和 UUID（Xcode 按 UUID 找文件）
    plist = plistlib.loads(content[content.index(b"<?xml"):content.index(b"</plist>") + len(b"</plist>")])
    os.makedirs(os.path.join(out, "profiles"), exist_ok=True)
    with open(os.path.join(out, "profiles", f"{plist['UUID']}.mobileprovision"), "wb") as f:
        f.write(content)
    return plist["TeamIdentifier"][0]


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    identifiers = os.environ["BUNDLE_IDS"].split()
    bundles = {identifier: find_bundle_id(identifier, register=i > 0) for i, identifier in enumerate(identifiers)}
    revoke_previous()
    certificate_id = create_certificate(out)
    try:
        team_ids = {create_profile(out, identifier, bundle, certificate_id) for identifier, bundle in bundles.items()}
    except BaseException:
        # 建了一半：吊销证书，用它的描述文件随之失效，下次运行开始时按名字删掉
        api("DELETE", f"/certificates/{certificate_id}", missing_ok=True)
        raise
    log(f"已建好证书和 {len(bundles)} 份描述文件")
    print(f"team_id={team_ids.pop()}")


if __name__ == "__main__":
    TOKEN = make_token()
    try:
        main()
    except ApiError as error:
        sys.exit(f"App Store Connect API 出错：{error}")

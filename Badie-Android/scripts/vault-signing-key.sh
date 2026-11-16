#!/usr/bin/env bash
# 安卓的签名密钥放在生产 Supabase 的 Vault 里（发版工作流 android-release.yml 用，见 docs/RELEASE.md 的“签名”）。
# 有就取出来；第一次运行时还没有，就生成一把（RSA 4096，别名 upload，CN=Badie），在一个事务里存进 Vault，再读出来用。
#
# 用法：VAULT_DB_URL=<数据库地址> PGPASSWORD=<数据库密码> vault-signing-key.sh <密钥库写到哪> <密码写到哪>
#
# 仓库是公开的：密钥库和密码不打印、不进命令行参数（psql 和 keytool 都从环境变量读），
# 在 GitHub Actions 里先用 ::add-mask:: 遮住再用。写出来的两个文件只有自己能读，用完由调用的人删掉。
set -euo pipefail
set +x

keystore_out=$1
password_out=$2
umask 077

KEYSTORE_NAME=android_signing_keystore
PASSWORD_NAME=android_signing_password

mask() {
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "$1" ]; then echo "::add-mask::$1"; fi
}

# -X 不读 ~/.psqlrc；出错只给一行（不带语句内容），别的输出都不要
sql() {
  psql "$VAULT_DB_URL" -X -q -At -v ON_ERROR_STOP=1 -v VERBOSITY=terse -v SHOW_CONTEXT=never
}

# 两个值一行，空格隔开（base64 和密码里都没有空格）；没有的是空的
read_vault() {
  sql <<SQL
select coalesce((select decrypted_secret from vault.decrypted_secrets where name = '$KEYSTORE_NAME'), '')
  || ' ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = '$PASSWORD_NAME'), '');
SQL
}

found=$(read_vault)
read -r keystore password <<<"$found" || true
unset found
mask "$keystore"
mask "$password"

if [ -z "$keystore" ] && [ -z "$password" ]; then
  echo "Vault 里还没有安卓签名密钥：生成一把新的（只在第一次）"
  NEW_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)
  mask "$NEW_PASSWORD"
  work=$(mktemp -d)
  NEW_PASSWORD="$NEW_PASSWORD" keytool -genkeypair -keystore "$work/new.p12" -storetype PKCS12 -alias upload \
    -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Badie" \
    -storepass:env NEW_PASSWORD -keypass:env NEW_PASSWORD >/dev/null 2>&1
  NEW_KEYSTORE=$(base64 -w0 "$work/new.p12")
  rm -rf "$work"
  mask "$NEW_KEYSTORE"
  export NEW_KEYSTORE NEW_PASSWORD
  # 两个一起存：要么都有，要么都没有。名字在 Vault 里是唯一的，两次运行同时走到这里时后一次会失败，下面重新读就是先存的那把
  if ! sql >/dev/null <<SQL
\\getenv new_keystore NEW_KEYSTORE
\\getenv new_password NEW_PASSWORD
begin;
select vault.create_secret(:'new_keystore', '$KEYSTORE_NAME', 'Badie Android signing keystore (PKCS12, base64). See Badie-Android/docs/RELEASE.md');
select vault.create_secret(:'new_password', '$PASSWORD_NAME', 'Password of $KEYSTORE_NAME (store and key)');
commit;
SQL
  then
    echo "没存进去（可能别的运行刚存好），重新读一次"
  fi
  unset NEW_KEYSTORE NEW_PASSWORD
  found=$(read_vault)
  read -r keystore password <<<"$found" || true
  unset found
  mask "$keystore"
  mask "$password"
fi

if [ -z "$keystore" ] || [ -z "$password" ]; then
  echo "::error::Supabase Vault 里的安卓签名密钥不完整（$KEYSTORE_NAME、$PASSWORD_NAME 要都有），见 Badie-Android/docs/RELEASE.md"
  exit 1
fi

printf '%s' "$keystore" | base64 --decode >"$keystore_out"
printf '%s' "$password" >"$password_out"
echo "签名密钥已从 Supabase Vault 取出"

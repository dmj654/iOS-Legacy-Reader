#!/usr/bin/env bash
# 一键部署脚本：用你的 GitHub PAT 创建公开仓库 iOS-Legacy-Reader 并推送，触发云端构建。
# 用法：
#   ./deploy.sh <GitHub_PAT> <你的GitHub用户名>
#
# 说明：
#   - 仓库为 PUBLIC，GitHub Actions 免费运行（macOS 官方镜像）
#   - 推送 main 分支后会自动触发 .github/workflows/build-ipa.yml
#   - 构建完成后会在 Actions Artifacts 与 Releases 中生成未签名 IPA
set -e

REPO="iOS-Legacy-Reader"
TOKEN="${1:-}"
USER="${2:-}"

if [ -z "$TOKEN" ] || [ -z "$USER" ]; then
  echo "用法: ./deploy.sh <GitHub_PAT> <GitHub用户名>"
  exit 1
fi

echo "==> 初始化 git 仓库"
git init -q
git config user.email "ci@legacydata.local"
git config user.name "Legacy Reader CI"
git add -A
git commit -q -m "Initial commit: iOS Legacy Reader (Legado 对标版)"

echo "==> 通过 API 创建公开仓库 $REPO"
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$REPO\",\"private\":false,\"auto_init\":false,\"description\":\"iOS 开源阅读(Legado)对标客户端 - 未签名可侧载 IPA\"}" \
  https://api.github.com/user/repos

echo "==> 推送到 main 分支"
git branch -M main
git remote add origin "https://$TOKEN@github.com/$USER/$REPO.git"
git push -u origin main

echo "==> 完成。请到 https://github.com/$USER/$REPO/actions 查看构建进度，"
echo "    构建成功后在 Releases 页面获取 IPA 下载直链。"

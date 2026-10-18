
#!/usr/bin/env bash
set -Eeuo pipefail

echo "========== Cudy TR3000 25.12 DIY 开始 =========="

# 确认当前目录是 OpenWrt 源码根目录
test -f Makefile
test -d package
test -d feeds

# --------------------------------------------------
# 2. 更新 Go 工具链
# PassWall 的 Xray 等组件可能需要较新的 Go 版本
# --------------------------------------------------
rm -rf feeds/packages/lang/golang

git clone --depth 1 --branch 27.x \
  https://github.com/sbwml/packages_lang_golang \
  feeds/packages/lang/golang

echo "Go 工具链已切换到 27.x 分支"

# --------------------------------------------------
# 3. 安装 PassWall 软件包
# --------------------------------------------------
for pkg in \
  xray-core v2ray-geodata sing-box chinadns-ng dns2socks \
  hysteria ipt2socks microsocks naiveproxy \
  shadowsocks-libev shadowsocks-rust shadowsocksr-libev \
  simple-obfs tcping trojan-plus tuic-client \
  v2ray-plugin xray-plugin geoview shadow-tls
do
  rm -rf "feeds/packages/net/$pkg"
done

rm -rf package/passwall-packages
git clone --depth 1 \
  https://github.com/Openwrt-Passwall/openwrt-passwall-packages \
  package/passwall-packages

rm -rf feeds/luci/applications/luci-app-passwall
rm -rf package/passwall2-luci

git clone --depth 1 \
  https://github.com/Openwrt-Passwall/openwrt-passwall2 \
  package/passwall2-luci

# --------------------------------------------------
# 4. 选择 PassWall2、Xray、Aria2、ksmbd
# --------------------------------------------------
cat >> .config <<'EOF'

# PassWall2
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_xray-core=y

# Aria2
CONFIG_PACKAGE_aria2=y
CONFIG_PACKAGE_luci-app-aria2=y

# Samba-compatible kernel SMB server
CONFIG_PACKAGE_ksmbd-server=y
CONFIG_PACKAGE_luci-app-ksmbd=y
CONFIG_PACKAGE_ksmbd-hotplug=y
CONFIG_PACKAGE_ksmbd-avahi-service=y

# USB storage and USB network adapters
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y

# Argon theme
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
EOF

# --------------------------------------------------
# 5. 检查 MTK 加速管理包
# 说明：只在源码中确实存在时才选中
# --------------------------------------------------
if find package feeds -type f \
  -path '*/luci-app-turboacc-mtk/Makefile' \
  -print -quit | grep -q .; then
  echo 'CONFIG_PACKAGE_luci-app-turboacc-mtk=y' >> .config
  echo "发现 luci-app-turboacc-mtk"
else
  echo "警告：新源码没有找到 luci-app-turboacc-mtk"
  echo "不会伪造软件包；请在编译日志中确认 HNAT/硬件加速支持。"
fi

if find package feeds -type f \
  -path '*/luci-app-eqos-mtk/Makefile' \
  -print -quit | grep -q .; then
  echo 'CONFIG_PACKAGE_luci-app-eqos-mtk=y' >> .config
fi

# --------------------------------------------------
# 6. 设置默认 LAN IP
# 使用首次启动脚本，不依赖旧版 config_generate 的默认 IP
# --------------------------------------------------
mkdir -p files/etc/uci-defaults

cat > files/etc/uci-defaults/99-cudy-default-lan-ip <<'EOF'
#!/bin/sh

uci -q set network.lan.ipaddr='192.168.10.1'
uci -q commit network

exit 0
EOF

chmod 755 files/etc/uci-defaults/99-cudy-default-lan-ip


# --------------------------------------------------
# 修复 MTK 软件包重复安装 l1dat / l1util 的冲突
# 由 l1util 软件包统一提供这两个文件
# --------------------------------------------------
python3 - <<'PY'
from pathlib import Path
import re

matches = []

for path in Path("package").rglob("Makefile"):
    content = path.read_text(errors="replace")
    if re.search(r"(?m)^define Package/mtwifi-cfg/install\s*$", content):
        matches.append((path, content))

if len(matches) != 1:
    print("ERROR: 无法唯一定位 mtwifi-cfg 的安装规则。")
    print("匹配到的文件：")
    for path, _ in matches:
        print(path)
    raise SystemExit(1)

path, content = matches[0]

pattern = re.compile(
    r"(?ms)(^define Package/mtwifi-cfg/install\s*\n)"
    r"(.*?)"
    r"(^endef\s*$)"
)

match = pattern.search(content)
if not match:
    raise SystemExit("ERROR: 找到 Makefile，但无法识别 install 规则。")

block = match.group(0)

if "rm -f $(1)/sbin/l1dat $(1)/sbin/l1util" in block:
    print("MTK 重复文件补丁已存在，跳过。")
else:
    new_block = (
        match.group(1)
        + match.group(2)
        + "\trm -f $(1)/sbin/l1dat $(1)/sbin/l1util\n"
        + match.group(3)
    )
    content = content[:match.start()] + new_block + content[match.end():]
    path.write_text(content)
    print(f"已修补：{path}")

PY

# --------------------------------------------------
# 7. 设置固件名称前缀
# --------------------------------------------------
if grep -q 'IMG_PREFIX:=' include/image.mk; then
  sed -i \
    's|IMG_PREFIX:=.*|IMG_PREFIX:=$(shell TZ="Asia/Shanghai" date +"%Y%m%d")-25.12-TR3000-|' \
    include/image.mk
fi

echo "========== Cudy TR3000 25.12 DIY 完成 =========="

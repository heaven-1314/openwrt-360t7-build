# ImmortalWrt 360T7 — daed 专用固件

为 **360T7 (MT7981)** 构建的 ImmortalWrt 固件，解决 daed 无法启动的问题。

## 为什么要做这个？

当前 ImmortalWrt 25.12 官方固件的 360T7 内核缺少两个关键配置：

| 缺失项 | 后果 |
|--------|------|
| `CONFIG_DEBUG_INFO_BTF` | `/sys/kernel/btf/vmlinux` 不存在 |
| BPF helper 支持 | daed 崩溃: `program of this type cannot use helper bpf_get_current_task#35` |

daed 依赖 eBPF 技术，需要内核同时具备 **BTF 数据** 和 **完整 BPF helper 支持**。官方固件两者都缺，所以 daed 进入 crash loop。

## 包含的软件

### 核心
- **daed** + **dae** + **luci-app-daede** (kenzok8 性能优化版)
- 所有 kmod 依赖 (sched-bpf, veth, xdp-sockets-diag, nft-tproxy)

### 用户请求插件
- **luci-app-turboacc** — 网络加速 (Shortcut FE + TCP BBR)
- **luci-theme-argon** — Argon 主题 + 配置器
- **luci-app-statistics** — 流量/性能监控 (collectd + RRD 图表)
- **luci-app-adblock-fast** — 广告过滤

### 基础系统
- LuCI 中文界面
- wpad (WPA3/sae 支持)
- IPv6 (odhcp6c + odhcpd)
- fw4 防火墙 (nftables)
- 实用工具 (curl, wget, bash, htop, nano, tcpdump)

## 使用方法

### 1. Fork / 推送到 GitHub

```bash
cd openwrt-360t7-build
git init
git add -A
git commit -m "feat: custom 360T7 firmware with daed + BTF kernel"
git remote add origin https://github.com/<你的用户名>/openwrt-360t7-build.git
git push -u origin main
```

### 2. 触发编译

进入 GitHub 仓库 → **Actions** 标签页 → **Build 360T7 Firmware** → **Run workflow**

编译时间：约 **2-3 小时**（GitHub Actions 免费额度足够）。

### 3. 下载固件

编译完成后，在 Action 运行页面的 **Artifacts** 区域下载 `immortalwrt-360t7-daed`。

### 4. 刷入固件

**方法 A — SSH sysupgrade（保留配置）**
```bash
scp *sysupgrade.bin root@192.168.100.1:/tmp/
ssh root@192.168.100.1
sysupgrade -v /tmp/*sysupgrade.bin
```

**方法 B — LuCI Web 界面**
1. 打开 `http://192.168.100.1`
2. 系统 → 备份/升级
3. 上传 sysupgrade.bin
4. 点击 "保留配置" → 执行升级

> ⚠️ **首次刷入建议不保留配置**（取消勾选），因为旧固件配置（daed crash loop）可能导致问题。
> 刷入后重新配置 WiFi、daed 等。

## 刷入后的配置

### 1. 基础网络
```bash
# 设置密码
passwd

# 配置 WiFi (参考你原来的配置)
uci set wireless.radio0.channel='1'
uci set wireless.radio0.hwmode='11g'
uci set wireless.radio0.htmode='HE40'
uci set wireless.default_radio0.ssid='OpenWrt'
uci set wireless.default_radio0.encryption='psk-mixed'
uci set wireless.default_radio0.key='<你的密码>'

uci set wireless.radio1.channel='64'
uci set wireless.radio1.hwmode='11a'
uci set wireless.radio1.htmode='HE160'
uci set wireless.default_radio1.ssid='Pandora'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio1.key='<你的密码>'

uci commit wireless
wifi reload
```

### 2. 恢复 daed 配置
```bash
# 恢复 wing.db
scp wing.db root@192.168.100.1:/etc/daed/

# 启动 daed
/etc/init.d/daed enable
/etc/init.d/daed start
```

### 3. 验证 BTF
```bash
# 确认 BTF 已可用
ls -la /sys/kernel/btf/vmlinux
# 应该输出: -r--r--r-- 1 root root <size> /sys/kernel/btf/vmlinux

# 确认 daed 正在运行
ps | grep daed
netstat -tlnp | grep 2023
```

## 文件结构

```
openwrt-360t7-build/
├── .github/workflows/
│   └── build.yml              # GitHub Actions 编译流程
├── config/
│   └── 360t7.seed             # 软件包选择配置
├── scripts/
│   ├── setup-feeds.sh         # 添加 kenzok8 daede 源
│   └── patch-kernel.sh        # 内核 BTF + BPF 补丁
├── .gitignore
└── README.md
```

## 内核补丁说明

`patch-kernel.sh` 修改以下内核配置：

| 配置项 | 作用 |
|--------|------|
| `CONFIG_DEBUG_INFO_BTF=y` | 生成 `/sys/kernel/btf/vmlinux` |
| `CONFIG_DEBUG_INFO=y` | BTF 依赖 |
| `CONFIG_BPF_SYSCALL=y` | BPF 系统调用 |
| `CONFIG_BPF_JIT=y` | BPF JIT 编译器 |
| `CONFIG_BPF_EVENTS=y` | BPF 事件（含 helper 支持） |
| `CONFIG_CGROUP_BPF=y` | cgroup BPF |
| `CONFIG_NET_CLS_BPF=m` | TC BPF 分类器 |
| `CONFIG_NET_ACT_BPF=m` | TC BPF 动作 |
| `CONFIG_XDP_SOCKETS=y` | XDP 套接字 |
| `CONFIG_VETH=m` | 虚拟以太网 |

## 自定义

### 添加/删除软件包

编辑 `config/360t7.seed`，添加或注释掉 `CONFIG_PACKAGE_*` 行。

### 更换 ImmortalWrt 分支

编辑 `.github/workflows/build.yml` 中的 `IMM_BRANCH` 环境变量。

### 更换 daede 源

编辑 `scripts/setup-feeds.sh` 中的 feed URL。

## 已知问题

- **`kmod-fast-classifier`**: MT7981 平台可能不支持 Shortcut FE 硬件加速。`luci-app-turboacc` 仍然可用（TCP BBR + DNS 加速），只是硬件 NAT 加速部分可能不可用。
- **首次编译时间**: 约 2-3 小时（含工具链编译）。后续编译因 ccache 缓存会更快。
- **GitHub Actions 限制**: 免费用户每月 2000 分钟。每次编译约消耗 180-200 分钟。

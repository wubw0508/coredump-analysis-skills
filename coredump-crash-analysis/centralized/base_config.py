"""
通用配置 - 系统库/插件库列表
这是通用基础配置，各包分析时可根据需要扩展
"""

# 系统库列表 (这些崩溃不需要修复)
# 基础库
BASIC_SYSTEM_LIBRARIES = {
    "libc.so.6", "libpthread.so.0", "librt.so.1", "libm.so.6",
    "libdl.so.2", "libresolv.so.2", "ld-linux", "libgcc_s.so.1",
}

# Qt库
QT_LIBRARIES = {
    "libQt5Core.so.5", "libQt5Widgets.so.5", "libQt5Gui.so.5",
    "libQt5DBus.so.5", "libQt5Network.so.5", "libQt5XcbQpa.so.5",
    "libQt5WaylandClient.so.5", "libQt5Wayland.so.5",
    "libQt6Core.so.6", "libQt6Widgets.so.6", "libQt6Gui.so.6",
}

# Dtk库
DTK_LIBRARIES = {
    "libdtkwidget.so.5", "libdtkgui.so.5", "libdtkcore.so.5",
    "libdtkcore.so.6", "libdtkgui.so.6", "libdtkwidget.so.6",
    "libdtkiconproxy.so", "libdtksettings.so.5",
}

# 图标/渲染库 (dde-launcher 相关)
ICON_LIBRARIES = {
    "libxdgicon.so", "libxdgicon.so.3",
    "libdsvgicon.so", "libdsvgicon.so.5",
    "libQt5Xdg.so", "libQt5XdgIconLoader.so", "libQt5XdgIconLoader.so.3",
    "librsvg-2.so.2", "libgdk_pixbuf-2.0.so.0", "libcairo.so.2",
}

# 系统库列表 (这些崩溃不需要修复)
SYSTEM_LIBRARIES = {
    # Qt库
    "libQt5Core.so.5", "libQt5Widgets.so.5", "libQt5Gui.so.5",
    "libQt5DBus.so.5", "libQt5Network.so.5", "libQt5XcbQpa.so.5",
    "libQt5WaylandClient.so.5", "libQt5Wayland.so.5",
    "libQt6Core.so.6", "libQt6Widgets.so.6", "libQt6Gui.so.6",
    # Wayland
    "libwayland-client.so.0", "libwayland-cursor.so.0",
    "libwayland-egl.so.1",
    # GLib
    "libglib-2.0.so.0", "libgobject-2.0.so.0", "libgio-2.0.so.0",
    # glibc
    "libc.so.6", "libpthread.so.0", "librt.so.1", "libm.so.6",
    "libdl.so.2", "libresolv.so.2", "libnss_*.so.2",
    # GCC/LLVM
    "libstdc++.so.6", "libgcc_s.so.1", "libc++.so.1",
    # Dtk
    "libdtkwidget.so.5", "libdtkgui.so.5", "libdtkcore.so.5",
    "libdtkcore.so.6", "libdtkgui.so.6", "libdtkwidget.so.6",
    # DBus
    "libdframeworkdbus.so.2", "libdframeworkdbus.so.3",
    "libdbus-1.so.3", "libdbus-glib-1.so.2",
    # X11
    "libX11.so.6", "libxcb.so.1", "libXext.so.6",
    "libXrender.so.1", "libXi.so.6", "libXfixes.so.3",
    # DRM/EGL/GL
    "libdrm.so.2", "libgbm.so.1", "libEGL.so.1", "libGL.so.1",
    "libGLdispatch.so.0", "libGLX.so.0",
    # FFI
    "libffi.so.6", "libffi.so.7",
    # BlueZ
    "libbluetooth.so.3", "libbluetooth.so.5",
    # systemd
    "libsystemd.so.0", "libsystemd.so.1",
    # PAM
    "libpam.so.1", "libpam_misc.so.1",
    # SSL
    "libssl.so.1.1", "libssl.so.3", "libcrypto.so.1.1", "libcrypto.so.3",
    # Other
    "librsvg-2.so.2", "libgdk_pixbuf-2.0.so.0", "libcairo.so.2",
    "libpango-1.0.so.0", "libgdk-3.so.0", "libgtk-3.so.0",
    "libmount.so.1", "libselinux.so.1", "libcap.so.2",
    "libaudit.so.1", "libnsl.so.1", "libshell.so.1",
    # 图标相关库
    "libxdgicon.so", "libxdgicon.so.3",
    "libdsvgicon.so", "libdsvgicon.so.5",
    "libQt5Xdg.so", "libQt5XdgIconLoader.so", "libQt5XdgIconLoader.so.3",
}

# 合并后的完整系统库
SYSTEM_LIBRARIES = (BASIC_SYSTEM_LIBRARIES | QT_LIBRARIES | DTK_LIBRARIES | ICON_LIBRARIES | {
    # Wayland
    "libwayland-client.so.0", "libwayland-cursor.so.0",
    "libwayland-egl.so.1",
    # GLib
    "libglib-2.0.so.0", "libgobject-2.0.so.0", "libgio-2.0.so.0",
    # 通配符
    "libnss_*.so.2",
    # DBus
    "libdframeworkdbus.so.2", "libdframeworkdbus.so.3",
    "libdbus-1.so.3", "libdbus-glib-1.so.2",
    # X11
    "libX11.so.6", "libxcb.so.1", "libXext.so.6",
    "libXrender.so.1", "libXi.so.6", "libXfixes.so.3",
    # DRM/EGL/GL
    "libdrm.so.2", "libgbm.so.1", "libEGL.so.1", "libGL.so.1",
    "libGLdispatch.so.0", "libGLX.so.0",
    # FFI
    "libffi.so.6", "libffi.so.7",
    # BlueZ
    "libbluetooth.so.3", "libbluetooth.so.5",
    # systemd
    "libsystemd.so.0", "libsystemd.so.1",
    # PAM
    "libpam.so.1", "libpam_misc.so.1",
    # SSL
    "libssl.so.1.1", "libssl.so.3", "libcrypto.so.1.1", "libcrypto.so.3",
    # Other
    "libpango-1.0.so.0", "libgdk-3.so.0", "libgtk-3.so.0",
    "libmount.so.1", "libselinux.so.1", "libcap.so.2",
    "libaudit.so.1", "libnsl.so.1", "libshell.so.1",
})

# 插件库列表 (这些崩溃记录但不需要修复主应用)
PLUGIN_LIBRARIES = {
    # dde-dock 插件
    "libtray.so", "libdatetime.so", "libbluetooth.so",
    "libeye-comfort-mode.so", "libsound.so",
    "libdde-disk-mount-plugin.so", "libdde-network-core.so",
    "libdde-bluetooth-plugin.so", "libnetwork.so",
    # 通用插件
    "libplugin.so", "libplugins.so", "libextension.so",
    # 托盘插件
    "libsnipetray.so", "libclipboard.so",
    # 各种插件后缀
    "-plugin.so", "_plugin.so", "plugin.so",
}

# 通用Gerrit配置
GERRIT_BASE_URL = "https://gerrit.uniontech.com"
GERRIT_API_URL = "https://gerrit.uniontech.com/r/a"

# 默认工作目录
DEFAULT_WORKSPACE = "/home/wubw/workspace"


def is_system_library(library: str) -> bool:
    """检查是否是系统库"""
    for sys_lib in SYSTEM_LIBRARIES:
        if sys_lib.endswith(".*"):
            # 通配符模式，如 libnss_*.so.2
            prefix = sys_lib[:-4]  # 移除 .*
            if library.startswith(prefix):
                return True
        elif sys_lib in library:
            return True
    return False


def is_plugin_library(library: str) -> bool:
    """检查是否是插件库"""
    for plugin in PLUGIN_LIBRARIES:
        if plugin in library:
            return True
    return False


# ============================================================
# 通用版本 TAG 映射表
# 格式: "deb版本号": "git tag"
# 用于崩溃分析时切换到正确的代码分支
# ============================================================
DEFAULT_VERSION_TAG_MAP = {
    # dde-launcher
    "5.5.33.2+zyd-1": "",
    "5.5.39-1": "",
    "5.5.41-1": "5.5.41",
    "5.5.42.1-1": "5.5.42.1",
    "5.6.15-1": "5.6.15",
    "5.6.15.1-1": "5.6.15.1",
    "5.6.19.1-1": "5.6.19.1",
    "5.6.19.2-1": "5.6.19.2",
    "5.6.19.3-1": "5.6.19.3",
    "5.7.9.5-1": "5.7.9.5",
    "5.7.9.7-1": "5.7.9.7",
    "5.7.16.1-1": "5.7.16.1",
    "5.7.17-1": "5.7.17.4",
    "5.7.20-1": "5.7.20.2",
    "5.7.20.3-1": "5.7.20.3",
    "5.7.25.1-1": "",
    "5.8.4-1": "5.8.4",
    "5.8.5-1": "5.8.5",
    "5.8.6-1": "5.8.6",
    # dde-dock (示例)
    "5.7.28.2-1": "5.7.28.2",
    "5.7.28.3-1": "5.7.28.3",
    "5.7.28.5-1": "5.7.28.5",
    "5.7.28.6-1": "5.7.28.6",
    "5.8.4.1-1": "5.8.4.1",
    "5.8.5.2-1": "5.8.5.2",
    "5.8.6.1-1": "5.8.6.1",
    "5.9.1.2-1": "5.9.1.2",
}

# 包名到 VERSION_TAG_MAP 的映射
PACKAGE_VERSION_TAG_MAPS = {
    "dde-launcher": DEFAULT_VERSION_TAG_MAP,
    "dde-dock": {
        "5.7.28.2-1": "5.7.28.2",
        "5.7.28.3-1": "5.7.28.3",
        "5.7.28.5-1": "5.7.28.5",
        "5.7.28.6-1": "5.7.28.6",
        "5.8.4.1-1": "5.8.4.1",
        "5.8.5.2-1": "5.8.5.2",
        "5.8.6.1-1": "5.8.6.1",
        "5.9.1.2-1": "5.9.1.2",
    },
}


def get_version_tag_map(package: str = "") -> dict:
    """获取指定包的 VERSION_TAG_MAP"""
    if package and package in PACKAGE_VERSION_TAG_MAPS:
        return PACKAGE_VERSION_TAG_MAPS[package]
    return DEFAULT_VERSION_TAG_MAP


def lookup_version_tag(version: str, package: str = "") -> str:
    """
    根据崩溃版本号查找对应的 git tag

    参数:
        version: 崩溃版本号 (如 "5.6.15.1-1")
        package: 包名 (可选)

    返回:
        git tag 字符串，如果找不到则返回空字符串
    """
    tag_map = get_version_tag_map(package)
    return tag_map.get(version, "")


def normalize_version(version: str) -> str:
    """
    标准化版本号
    去除 epoch '1:' 前缀和 debian 修订号 '-1'
    """
    import re
    # 去除 epoch
    version = re.sub(r'^1:', '', version)
    # 去除 debian 修订号
    version = re.sub(r'-1$', '', version)
    return version

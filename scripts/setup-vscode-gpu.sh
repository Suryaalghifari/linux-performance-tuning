#!/usr/bin/env bash
# Configure VS Code GPU rasterization and RAM disk caching
set -euo pipefail

echo "[+] Configuring VS Code Hardware Acceleration..."

# 1. Ensure RAM disk directory exists
mkdir -p -m 777 /dev/shm/vscode-cache

# 2. Deploy desktop override
TARGET_DIR="$HOME/.local/share/applications"
mkdir -p "$TARGET_DIR"

cat << 'EOF' > "$TARGET_DIR/code_code.desktop"
[Desktop Entry]
X-SnapInstanceName=code
Name=Visual Studio Code
Comment=Code Editing. Redefined.
GenericName=Text Editor
X-SnapAppName=code
X-SnapCommonID=code.desktop
Exec=/snap/bin/code --force-user-env --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache %F
Icon=/snap/code/current/meta/gui/vscode.png
Type=Application
StartupNotify=false
StartupWMClass=code_code
Categories=TextEditor;Development;IDE;
MimeType=application/x-code-workspace;
Actions=new-empty-window;
Keywords=vscode;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=/snap/bin/code --force-user-env --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache --new-window %F
Icon=/snap/code/current/meta/gui/vscode.png
EOF

update-desktop-database "$TARGET_DIR" 2>/dev/null || true
echo "[+] Desktop launcher installed to $TARGET_DIR/code_code.desktop"

# 3. Add shell wrapper to suppress Chromium CLI warnings in Fish / Bash
if [ -f "$HOME/.config/fish/config.fish" ]; then
    if ! grep -q "command /snap/bin/code --enable-gpu-rasterization" "$HOME/.config/fish/config.fish"; then
        cat << 'EOF' >> "$HOME/.config/fish/config.fish"

function code
    command /snap/bin/code --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache $argv 2>&1 | string match -v "*is not in the list of known options*"
end
EOF
        echo "[+] Fish shell wrapper function added."
    fi
fi

if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "alias code=" "$HOME/.bashrc"; then
        echo 'alias code="code --enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --disk-cache-dir=/dev/shm/vscode-cache"' >> "$HOME/.bashrc"
        echo "[+] Bash alias added."
    fi
fi

#!/bin/bash
# 设置删除键行为
stty erase "^?"

# 检查Realm是否已安装
if [ -f "/root/realm/realm" ]; then
    echo "检测到Realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "Realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查Realm服务状态
check_realm_service_status() {
    # 检查转发规则数量
    local rule_count=$(grep -c '^\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null || echo "0")
    
    if systemctl is-active --quiet realm && [ "$rule_count" -gt 0 ]; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo " "    
    echo "          欢迎使用Realm一键转发脚本CN境内加速版"
    echo " ———————————— Realm版本v2.9.2 ————————————"
    echo "     修改by：Ois    修改日期：2025/04/16"
    echo " "
    echo "—————————————————————"
    echo " 1. 安装 Realm"
    echo "—————————————————————"
    echo " 2. 添加 Realm 转发规则"
    echo " 3. 查看 Realm 转发规则"
    echo " 4. 修改 Realm 转发规则"
    echo " 5. 删除 Realm 转发规则"
    echo "—————————————————————"
    echo " 6. 启动 Realm 服务"
    echo " 7. 停止 Realm 服务"
    echo " 8. 重启 Realm 服务"
    echo "—————————————————————"
    echo " 9. 卸载 Realm"
    echo "—————————————————————"
    echo " 10. 定时重启任务"
    echo "—————————————————————"
    echo " 11. 导出转发规则"
    echo " 12. 导入转发规则"
    echo "—————————————————————"
    echo " 0. 退出脚本"
    echo "—————————————————————"
    echo " "
    echo -e "Realm 状态：${realm_status_color}${realm_status}\033[0m"
    echo -n "Realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm
    wget -O realm.tar.gz https://ghfast.top/https://github.com/zhboner/realm/releases/download/v2.9.2-2/realm-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf realm.tar.gz
    chmod +x realm
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload

    # 服务启动后，检查config.toml是否存在，如果不存在则创建
    if [ ! -f /root/realm/config.toml ]; then
        touch /root/realm/config.toml
    fi

    # 检查 config.toml 中是否已经包含 [network] 配置块
    network_count=$(grep -c '^\[network\]' /root/realm/config.toml)

    if [ "$network_count" -eq 0 ]; then
        # 如果没有找到 [network]，将其添加到文件顶部
        echo "[network]
no_tcp = false
use_udp = true
" | cat - /root/realm/config.toml > temp && mv temp /root/realm/config.toml
        echo "[network] 配置已添加到 config.toml 文件。"
    
    elif [ "$network_count" -gt 1 ]; then
        # 如果找到多个 [network]，删除多余的配置块，只保留第一个
        sed -i '0,/^\[\[endpoints\]\]/{//!d}' /root/realm/config.toml
        echo "[network]
no_tcp = false
use_udp = true
" | cat - /root/realm/config.toml > temp && mv temp /root/realm/config.toml
        echo "多余的 [network] 配置已删除。"
    else
        echo "[network] 配置已存在，跳过添加。"
    fi

    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -rf /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf /root/realm
    rm -rf "$(pwd)"/realm.sh
    sed -i '/realm/d' /etc/crontab
    echo "Realm已被卸载。"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 显示当前所有规则的辅助函数
show_current_rules() {
    # 接收一个参数作为提示消息
    local message=${1:-"操作完成"}
    
    clear
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n'
    local lines=($(grep -n 'listen =' /root/realm/config.toml 2>/dev/null || echo ""))
    
    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "没有发现任何转发规则。"
    else
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
            
            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
    fi
    
    echo -e "\n$message，按回车键返回主菜单..."
    read  # 等待用户按回车键
}

# 修改转发规则的函数
modify_forward() {
    clear  # 清屏
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
    local lines=($(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null || echo ""))
    
    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
        local listen_info=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)

        printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
        echo -e "---------------------------------------------------------------------"
        let index+=1
    done

    echo "请输入要修改的转发规则序号，取消直接按回车键返回主菜单。"
    read -e -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local chosen_line=${lines[$((choice-1))]}
    local start_line=$(echo $chosen_line | cut -d ':' -f 1)
    local remark_line=$((start_line + 1))
    local listen_line=$((start_line + 2))
    local remote_line=$((start_line + 3))

    # 获取当前值
    local current_remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
    local current_listen=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
    local current_remote=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)
    
    # 提取当前的本地端口
    local current_local_port=$(echo "$current_listen" | grep -o '[0-9]\+$')
    
    # 修复IPv6地址解析问题
    # 判断是否是IPv6地址（检查是否包含方括号）
    if [[ "$current_remote" == \[*\]* ]]; then
        # IPv6地址格式：[IPv6地址]:端口
        local current_remote_ip=$(echo "$current_remote" | sed -E 's/\[(.*)\]:.*/\1/')
        local current_remote_port=$(echo "$current_remote" | sed -E 's/.*\]:(.*)/\1/')
    else
        # IPv4地址格式：IPv4地址:端口
        local current_remote_ip=$(echo "$current_remote" | cut -d ':' -f 1)
        local current_remote_port=$(echo "$current_remote" | cut -d ':' -f 2)
    fi

    echo -e "\n---------------------------------------------------------------------"
    echo -e "                           当前配置信息                           "
    echo -e "---------------------------------------------------------------------"
    echo -e " 本地端口: $current_local_port"
    echo -e " 远程地址: $current_remote_ip"
    echo -e " 远程端口: $current_remote_port"
    echo -e " 转发备注: $current_remark"
    echo -e "---------------------------------------------------------------------"
    echo -e "                 请输入新的值（直接回车保持不变）                 "
    echo -e "---------------------------------------------------------------------"

    read -e -p " 新的本地端口 [$current_local_port]: " new_local_port
    read -e -p " 新的远程地址 [$current_remote_ip]: " new_remote_ip
    read -e -p " 新的远程端口 [$current_remote_port]: " new_remote_port
    read -e -p " 新的转发备注 [$current_remark]: " new_remark
    
    # 如果用户没有输入新值，则使用当前值
    new_local_port=${new_local_port:-$current_local_port}
    new_remote_ip=${new_remote_ip:-$current_remote_ip}
    new_remote_port=${new_remote_port:-$current_remote_port}
    new_remark=${new_remark:-$current_remark}
    
    # 处理IPv6地址的特殊格式
    if [[ "$new_remote_ip" == \[*\]* ]]; then
        # 已经包含方括号的 IPv6 地址，直接添加端口
        remote_format="$new_remote_ip:$new_remote_port"
    elif [[ "$new_remote_ip" == *:*:* ]]; then
        # 不包含方括号的 IPv6 地址，需要添加方括号
        remote_format="[$new_remote_ip]:$new_remote_port"
    else
        # IPv4 地址或主机名
        remote_format="$new_remote_ip:$new_remote_port"
    fi
    
    # 更新配置文件
    sed -i "${remark_line}s/^# 备注:.*$/# 备注: $new_remark/" /root/realm/config.toml
    sed -i "${listen_line}s/listen = \".*\"/listen = \"[::]:$new_local_port\"/" /root/realm/config.toml
    sed -i "${remote_line}s/remote = \".*\"/remote = \"$remote_format\"/" /root/realm/config.toml
    
    echo -e "\n---------------------------------------------------------------------"
    echo -e "                          转发规则已更新                          "
    echo -e "---------------------------------------------------------------------"
    
    # 重启服务
    sudo systemctl restart realm.service
    echo "Realm服务已重新启动。"
    
    # 显示当前规则
    show_current_rules "规则修改完成"
    
    # 使用全局变量避免重复按键
    key=1  # 设置一个非空值，使主循环中的read跳过
}



# 删除转发规则的函数
delete_forward() {
    # 标记是否进行了删除操作
    local has_deleted=false
    
    while true; do
        clear  # 清屏，确保每次只显示一个规则列表
        echo -e "                      当前 Realm 转发规则                      "
        echo -e "---------------------------------------------------------------------"
        local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
        # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
        local lines=($(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null || echo ""))
        
        if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
            echo "没有发现任何转发规则。"
            if [ "$has_deleted" = true ]; then
                echo "所有规则已删除，正在重启 Realm 服务以应用更改..."
                sudo systemctl restart realm.service
                echo "Realm服务已重新启动。"
                # 设置标记，避免主循环中重复按键，但不需要显示规则列表
                key=1
            fi
            echo "按回车键返回主菜单..."
            read -e  # 用户只需要按一次回车
            return
        fi

        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local remark_line=$((line_number + 1))
            local listen_line=$((line_number + 2))
            local remote_line=$((line_number + 3))

            local remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
            local listen_info=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)
            
            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done

        echo "请输入要删除的转发规则序号，取消直接按回车键返回主菜单。"
        read -e -p "选择: " choice
        if [ -z "$choice" ]; then
            # 如果有删除操作，则在返回主菜单前重启服务
            if [ "$has_deleted" = true ]; then
                echo "正在重启 Realm 服务以应用更改..."
                sudo systemctl restart realm.service
                echo "Realm服务已重新启动。"
                # 设置标记，避免主循环中重复按键，但不需要显示规则列表
                key=1
            else
                echo "未进行任何删除操作。"
            fi
            return
        fi

        if ! [[ $choice =~ ^[0-9]+$ ]]; then
            echo "无效输入，请输入数字。"
            continue
        fi

        if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
            echo "选择超出范围，请输入有效序号。"
            continue
        fi

        local chosen_line=${lines[$((choice-1))]}
        local start_line=$(echo $chosen_line | cut -d ':' -f 1)

        # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
        local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

        if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
            # 如果没有找到下一个 [[endpoints]]，则删除到文件末尾
            end_line=$(wc -l < /root/realm/config.toml)
        else
            # 如果找到了下一个 [[endpoints]]，则删除到它的前一行
            end_line=$((next_endpoints_line - 1))
        fi

        # 使用 sed 删除指定行范围的内容
        sed -i "${start_line},${end_line}d" /root/realm/config.toml

        # 检查并删除可能多余的空行
        sed -i '/^\s*$/d' /root/realm/config.toml

        echo "转发规则及其备注已删除。"
        
        # 标记已进行删除操作
        has_deleted=true
    done
}

# 查看转发规则
show_all_conf() {
    clear  # 清屏
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 listen 的行，表示转发规则的起始行
    local lines=($(grep -n 'listen =' /root/realm/config.toml 2>/dev/null || echo ""))
    
    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
        
        printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
        echo -e "---------------------------------------------------------------------"
        let index+=1
    done
}

# 添加转发规则
add_forward() {
    clear  # 清屏
    # 先显示当前已经添加的规则列表
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n'
    local lines=($(grep -n 'listen =' /root/realm/config.toml 2>/dev/null || echo ""))
    
    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "目前没有任何转发规则。"
    else
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
            
            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
    fi
    
    echo -e "\n现在添加新的转发规则: (取消按回车键返回主菜单)"
    
    local has_added=false  # 标记是否添加了规则
    
    while true; do
        read -e -p "请输入本地监听端口: " local_port
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$local_port" ]; then
            echo "未输入端口，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                sudo systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi
        
        read -e -p "请输入需要转发的IP: " ip
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$ip" ]; then
            echo "未输入IP，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                sudo systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi
        
        read -e -p "请输入需要转发端口: " port
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$port" ]; then
            echo "未输入转发端口，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                sudo systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi
        
        # 备注可以为空，不做检查
        read -e -p "请输入备注(支持中文，可为空): " remark
        
        # 处理IPv6地址的特殊格式
        if [[ "$ip" == \[*\]* ]]; then
            # 已经包含方括号的 IPv6 地址，直接添加端口
            remote_format="$ip:$port"
        elif [[ "$ip" == *:*:* ]]; then
            # 不包含方括号的 IPv6 地址，需要添加方括号
            remote_format="[$ip]:$port"
        else
            # IPv4 地址或主机名
            remote_format="$ip:$port"
        fi
        
        # 追加到config.toml文件
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$remote_format\"" >> /root/realm/config.toml
        
        # 标记已添加规则
        has_added=true
        
        read -e -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
        
        # 如果用户选择继续添加，清屏并显示更新后的规则列表
        clear
        echo -e "                      当前 Realm 转发规则                      "
        echo -e "---------------------------------------------------------------------"
        local lines=($(grep -n 'listen =' /root/realm/config.toml 2>/dev/null || echo ""))
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
            
            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
        echo -e "\n继续添加新的转发规则: (取消按回车键返回主菜单)"
    done
    
    # 只有在添加了规则才重启服务
    if [ "$has_added" = true ]; then
        sudo systemctl restart realm.service
        echo "Realm服务已重新启动，转发规则已应用。"
        
        # 显示当前所有规则
        show_current_rules "规则添加完成"
        
        # 使用全局变量避免重复按键
        key=1  # 设置一个非空值，使主循环中的read跳过
    fi
}



# 导出转发规则
export_rules() {
    clear
    echo -e "                      Realm转发规则导出                      "
    echo -e "---------------------------------------------------------------------"
    
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    
    # 搜索所有包含 [[endpoints]] 的行
    local lines=($(grep -n '^\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null || echo ""))
    
    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
        local listen_info=$(sed -n "${listen_line}p" /root/realm/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" /root/realm/config.toml | cut -d '"' -f 2)

        # 提取本地端口
        local local_port=$(echo "$listen_info" | grep -o '[0-9]\+$')
        
        # 输出格式化的数据行
        echo "$index|$local_port|$remote_info|$remark"
        
        let index+=1
    done
    # 在函数结尾处：
    echo -e "---------------------------------------------------------------------"
    echo -e "已导出 $((index-1)) 条转发规则，请复制保存。"
}

# 导入转发规则
import_rules() {
    clear
    echo -e "                      Realm转发规则导入                      "
    echo -e "---------------------------------------------------------------------"
    echo -e "请按照以下格式粘贴转发规则："
    echo -e "序号|本地端口|远程IP:端口|备注"
    echo " "  
    echo -e "例如："
    echo -e "1|8080|192.168.1.1:8000|一号服务器"
    echo -e "2|8443|192.168.1.2:9000|二号服务器"
    echo -e "3|9000|[2001:db8::1]:8080|IPv6服务器"
    echo " "  
    echo -e "---------------------------------------------------------------------"
    echo -e "请在下方粘贴规则（粘贴完成后按Ctrl+D结束输入）："
    
    # 创建临时文件存储用户输入
    local temp_file=$(mktemp)
    
    # 读取用户输入到临时文件
    cat > "$temp_file"
    
    # 获取输入行数
    local line_count=$(wc -l < "$temp_file")
    
    if [ "$line_count" -eq 0 ]; then
        echo "未输入任何规则。"
        rm "$temp_file"
        return
    fi
    
    # 添加换行，确保与用户输入分开显示
    echo -e "\n检测到 $line_count 条规则，准备导入..."
    read -e -p "是否确认导入？这将添加新的规则，不会覆盖现有规则 (Y/N): " confirm
    
    if [[ $confirm != "Y" && $confirm != "y" ]]; then
        echo "已取消导入。"
        rm "$temp_file"
        return
    fi
    
    local success_count=0
    
    # 逐行处理导入的数据
    while IFS='|' read -r index local_port remote_addr remark || [ -n "$index" ]; do
        # 跳过空行或格式不正确的行
        if [ -z "$index" ] || [ -z "$local_port" ] || [ -z "$remote_addr" ]; then
            continue
        fi
        
        # 跳过不以数字开头的行（可能是表头）
        if ! [[ $index =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        # 处理IPv6地址的格式
        if [[ "$remote_addr" != \[*\]* ]] && [[ "$remote_addr" == *:*:* ]]; then
            # 检测到未格式化的IPv6地址（包含多个冒号但不是以[开头）
            # 尝试提取最后一个冒号后的内容作为端口号
            local remote_port="${remote_addr##*:}"
            # 去除最后一部分（端口号）
            local remote_ip="${remote_addr%:$remote_port}"
            # 重新组装为正确的IPv6格式
            remote_addr="[$remote_ip]:$remote_port"
        fi
        
        # 添加到config.toml
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$remote_addr\"" >> /root/realm/config.toml
        
        let success_count+=1
    done < "$temp_file"
    
    rm "$temp_file"
    
    if [ $success_count -gt 0 ]; then
        echo "成功导入 $success_count 条转发规则。"
        # 重启服务
        sudo systemctl restart realm.service
        echo "Realm服务已重新启动。"
        # 显示当前规则
        show_current_rules "规则导入完成"
        # 使用全局变量避免重复按键
        key=1
    else
        echo "没有导入任何规则，请检查输入格式是否正确。"
    fi
}

# 自定义显示服务状态的函数
show_service_status() {
    # 检查服务是否活动
    if systemctl is-active --quiet realm; then
        # 服务活动时显示绿色圆点
        echo -e "\033[0;32m●\033[0m realm.service - realm"
    else
        # 服务不活动时显示红色圆点
        echo -e "\033[0;31m●\033[0m realm.service - realm"
    fi
    
    # 显示其他状态信息
    systemctl status realm.service --no-pager | tail -n +2 | head -n 4
}

# 启动服务
start_service() {
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    
    # 检查服务是否成功启动
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功启动并设置为开机自启。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务启动失败！\033[0m"  # 红色
    fi
    
    echo "Realm 服务状态："
    show_service_status
}

# 停止服务
stop_service() {
    systemctl stop realm
    
    # 检查服务是否成功停止
    if ! systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功停止。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务停止失败！\033[0m"  # 红色
    fi
    
    echo "Realm 服务状态："
    show_service_status
}

# 重启服务
restart_service() {
    sudo systemctl stop realm
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    
    # 检查服务是否成功重启
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功重启。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务重启失败！\033[0m"  # 红色
    fi
    
    echo "Realm 服务状态："
    show_service_status
}

# 定时任务
cron_restart() {
    clear
    echo -e "---------------------------------------------------------------------"
    echo -e "                        Realm定时重启任务                        "
    echo -e "---------------------------------------------------------------------"
    echo -e "[1] 配置Realm定时重启任务"
    echo -e "[2] 删除Realm定时重启任务"
    echo -e "---------------------------------------------------------------------"
    read -e -p "请选择: " numcron
    if [ "$numcron" == "1" ]; then
        echo -e "---------------------------------------------------------------------"
        echo -e "                      Realm定时重启任务类型                      "
        echo -e "---------------------------------------------------------------------"
        echo -e "[1] 每？小时重启"
        echo -e "[2] 每日？点重启"
        echo -e "---------------------------------------------------------------------"
        read -e -p "请选择: " numcrontype
        if [ "$numcrontype" == "1" ]; then
            echo -e "---------------------------------------------------------------------"
            read -e -p "每？小时重启: " cronhr
            echo "0 */$cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
            echo -e "定时重启设置成功！"
        elif [ "$numcrontype" == "2" ]; then
            echo -e "---------------------------------------------------------------------"
            read -e -p "每日？点重启: " cronhr
            echo "0 $cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
            echo -e "定时重启设置成功！"
        else
            echo "输入错误，请重试"
            return
        fi
    elif [ "$numcron" == "2" ]; then
        sed -i "/realm/d" /etc/crontab
        echo -e "定时重启任务删除完成！"
    else
        echo "输入错误，请重试"
        return
    fi
}

# 主循环
while true; do
    show_menu
    read -e -p "请选择一个选项[0-12]: " choice
    # 去掉输入中的空格
    choice=$(echo $choice | tr -d '[:space:]')

    # 检查输入是否为数字，并在有效范围内
    if ! [[ "$choice" =~ ^([0-9]|1[0-2])$ ]]; then
        echo "无效选项: $choice"
        continue
    fi

    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            # 如果key变量有值，说明刚从添加完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        3)
            show_all_conf
            ;;
        4)
            modify_forward
            # 如果key变量有值，说明刚从修改完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        5)
            delete_forward
            # 如果key变量有值，说明刚从删除完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        6)
            start_service
            ;;
        7)
            stop_service
            ;;
        8)
            restart_service
            ;;
        9)
            uninstall_realm
            ;;
        10)
            cron_restart
            ;;  
        11)
            export_rules
            ;;
        12)
            import_rules
            # 如果key变量有值，说明刚从导入完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        0)
            echo "退出脚本。"  # 显示退出消息
            exit 0            # 退出脚本
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
    
    # 如果key变量有值，说明刚从某个操作完成界面返回，无需再次等待按键
    if [ -n "$key" ]; then
        key=""  # 清空key变量
        continue
    fi
    
    read -e -p "按任意键返回主菜单..." key
done

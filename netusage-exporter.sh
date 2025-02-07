#!/bin/bash

# 加载配置文件
CONFIG_FILE="/root/exporter/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "错误：配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 验证必要的配置项
required_vars=("INTERFACE" "BILLING_DAY" "METRIC_PREFIX" "INSTANCE_NAME" "JOB_NAME")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "错误：配置项 $var 未设置"
        exit 1
    fi
done

# 设置默认值
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}
PROMETHEUS_HOST=${PROMETHEUS_HOST:-"127.0.0.1"}
PROMETHEUS_PORT=${PROMETHEUS_PORT:-"8429"}
current_time=$(date +%s%3N)

# 自动获取当前日期
current_date=$(date +"%Y-%m-%d")



# 将当前日期转换为时间戳
current_date_epoch=$(date -d "$current_date" +%s)

# 计算本月账单日的时间戳
current_month=$(date -d "$current_date" +%m)
current_year=$(date -d "$current_date" +%Y)
billing_date="$current_year-$current_month-$BILLING_DAY"
billing_date=$(date -d "$billing_date" +"%Y-%m-%d")

# 如果当前日期小于账单日，使用上个月的账单日
# echo "$current_date"
# echo "$billing_date"
if [[ "$current_date" < "$billing_date" ]]; then
  last_billing_date=$(date -d "$current_year-$((current_month-1))-$BILLING_DAY" +%s)
  billing_date=$(date -d "$current_year-$((current_month-1))-$BILLING_DAY" +"%Y-%m-%d")
else
  last_billing_date=$(date -d "$billing_date" +%s)
fi

# 假设 vnstat_data 变量包含 JSON 数据
vnstat_data=$(vnstat -i $INTERFACE --json d --limit 31)
# echo "$vnstat_data"

# 使用 jq 从变量 vnstat_data 提取流量数据并分别赋值给 total_rx 和 total_tx
read total_rx total_tx <<< $(echo "$vnstat_data" | jq -r --arg start_date "$last_billing_date" --arg end_date "$current_date_epoch" '
  .interfaces[0].traffic.day | 
  map(select(.timestamp >= ($start_date|tonumber) and .timestamp <= ($end_date|tonumber))) |
  reduce .[] as $item ({"rx": 0, "tx": 0}; 
    .rx += $item.rx | 
    .tx += $item.tx) | 
  "\(.rx) \(.tx)"
')

# 输出结果
#echo "Total RX: $total_rx"
# echo "Total TX: $total_tx"

if [[ $total_rx -eq 0 && $total_tx -eq 0 ]]; then
    echo "账单周期 ($billing_date 到 $current_date) 内无流量记录。"
else
    echo "从账单日 ($billing_date) 到今天 ($current_date) 的流量统计："
    echo "下载流量：$((total_rx / 1024 / 1024)) MB"
    echo "上传流量：$((total_tx / 1024 / 1024)) MB"
fi

# 构建 Prometheus 格式的数据
PROMETHEUS_DATA="${METRIC_PREFIX}_transmit_bytes_total{job=\"${JOB_NAME}\",instance=\"${INSTANCE_NAME}\",billing_day=\"${BILLING_DAY}\",billing_both_ways=\"${BILLING_BOTH_WAYS}\",monthly_quota=\"${MONTHLY_QUOTA}\"} ${total_tx} ${current_time}
${METRIC_PREFIX}_receive_bytes_total{job=\"${JOB_NAME}\",instance=\"${INSTANCE_NAME}\",billing_day=\"${BILLING_DAY}\",billing_both_ways=\"${BILLING_BOTH_WAYS}\",monthly_quota=\"${MONTHLY_QUOTA}\"} ${total_rx} ${current_time}"

# 发送数据到 Prometheus 的函数
send_to_prometheus() {
    local data="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if echo "$data" | curl -s -f \
            -X POST \
            -H "Content-Type: text/plain" \
            -u "${PROMETHEUS_USER}:${PROMETHEUS_PASSWORD}" \
            --data-binary @- \
            "http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}/api/v1/import/prometheus"; then
            echo "数据发送成功"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $MAX_RETRIES ]; then
                echo "发送失败，等待 ${RETRY_DELAY} 秒后进行第 $retry_count 次重试..."
                sleep $RETRY_DELAY
            else
                echo "发送失败，已达到最大重试次数 ${MAX_RETRIES}"
            fi
        fi
    done
    
    return 1
}

# 打印调试信息
echo "准备发送的数据："
echo "$PROMETHEUS_DATA"
echo "----------------------------------------"

# 发送数据
if send_to_prometheus "$PROMETHEUS_DATA"; then
    # 验证数据
    echo "----------------------------------------"
    echo "验证数据："
    curl -s -u "${PROMETHEUS_USER}:${PROMETHEUS_PASSWORD}" \
        "http://${PROMETHEUS_HOST}:8428/api/v1/query?query=${METRIC_PREFIX}_receive_bytes_total" | jq .
else
    echo "发送数据失败"
    exit 1
fi